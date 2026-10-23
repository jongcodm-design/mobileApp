package com.example.class_schedule

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.util.Calendar
import java.util.Locale

private data class ScheduledWidgetClass(
    val subject: String,
    val room: String,
    val professor: String,
    val day: Int,
    val startMinutes: Int,
    val endMinutes: Int,
)

private data class NextWidgetClass(
    val item: ScheduledWidgetClass,
    val isHappeningNow: Boolean,
    val millisToBoundary: Long,
)

class NextClassWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val classes = readSchedule(context)
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId, classes)
        }
        scheduleNextBoundary(context, classes)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(
            context,
            appWidgetManager,
            appWidgetId,
            newOptions,
        )
        updateWidget(context, appWidgetManager, appWidgetId, readSchedule(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            BOUNDARY_ACTION,
            -> updateAllWidgets(context)
        }
    }

    companion object {
        const val PREFERENCES_NAME = "classcue_next_class_widget"
        const val SCHEDULE_KEY = "saved_schedule_json"

        // Fires just after the next class starts or ends so the "In class" label
        // and the status line change on time instead of waiting for the 30-minute refresh.
        private const val BOUNDARY_ACTION = "com.example.class_schedule.NEXT_CLASS_BOUNDARY"
        private const val BOUNDARY_REQUEST_CODE = 4217

        // Compact layouts keep a one-line subject and class time; the two
        // metadata rows appear only when the launcher provides enough height.
        private const val FULL_LAYOUT_MIN_HEIGHT_DP = 140
        private const val TIME_MIN_HEIGHT_DP = 70
        private const val DETAILS_MIN_HEIGHT_DP = 80

        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NextClassWidgetProvider::class.java)
            val widgetIds = manager.getAppWidgetIds(component)
            if (widgetIds.isNotEmpty()) {
                NextClassWidgetProvider().onUpdate(context, manager, widgetIds)
            }
        }

        private fun readSchedule(context: Context): List<ScheduledWidgetClass> {
            val preferences = context.getSharedPreferences(
                PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            val scheduleJson = preferences.getString(SCHEDULE_KEY, "[]") ?: "[]"
            return try {
                val array = JSONArray(scheduleJson)
                buildList {
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: continue
                        val day = item.optInt("day", 0)
                        val start = item.optInt("start_minutes", -1)
                        val end = item.optInt("end_minutes", -1)
                        val subject = item.optString("subject").trim()
                        if (
                            day !in 1..7 ||
                            start < 0 ||
                            start >= 1440 ||
                            end < 1 ||
                            end > 1440 ||
                            end <= start ||
                            subject.isEmpty()
                        ) {
                            continue
                        }
                        add(
                            ScheduledWidgetClass(
                                subject = subject,
                                room = item.optString("room").trim(),
                                professor = item.optString("professor").trim(),
                                day = day,
                                startMinutes = start,
                                endMinutes = end,
                            ),
                        )
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun scheduleNextBoundary(context: Context, classes: List<ScheduledWidgetClass>) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            val intent = Intent(context, NextClassWidgetProvider::class.java)
                .setAction(BOUNDARY_ACTION)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                BOUNDARY_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.cancel(pendingIntent)
            if (classes.isEmpty()) return
            val now = Calendar.getInstance()
            val triggerAt = listOfNotNull(
                nextBoundaryMillis(classes, now),
                nextMinuteUpdateMillis(now),
            ).minOrNull() ?: return
            // Inexact on purpose: no exact-alarm permission needed, and a few
            // minutes of drift is acceptable for a minute-granularity countdown.
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC, triggerAt, pendingIntent)
        }

        private fun nextMinuteUpdateMillis(now: Calendar): Long {
            val millisIntoMinute =
                now.get(Calendar.SECOND) * 1_000L + now.get(Calendar.MILLISECOND)
            // Refresh just after the minute changes so the displayed rounded
            // countdown stays in sync with the in-app hero.
            return now.timeInMillis - millisIntoMinute + 60_000L + 1_000L
        }

        private fun nextBoundaryMillis(
            classes: List<ScheduledWidgetClass>,
            now: Calendar,
        ): Long? {
            if (classes.isEmpty()) return null
            val today = when (now.get(Calendar.DAY_OF_WEEK)) {
                Calendar.SUNDAY -> 7
                else -> now.get(Calendar.DAY_OF_WEEK) - 1
            }
            val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            var soonestMinutes: Int? = null
            for (item in classes) {
                for (boundary in listOf(item.startMinutes, item.endMinutes)) {
                    val dayDifference = (item.day - today + 7) % 7
                    var minutesUntil = dayDifference * 1440 + boundary - nowMinutes
                    if (minutesUntil <= 0) minutesUntil += 7 * 1440
                    if (soonestMinutes == null || minutesUntil < soonestMinutes) {
                        soonestMinutes = minutesUntil
                    }
                }
            }
            val minutesUntilMidnight = 1440 - nowMinutes
            if (minutesUntilMidnight > 0 && (soonestMinutes == null || minutesUntilMidnight < soonestMinutes)) {
                soonestMinutes = minutesUntilMidnight
            }
            val secondsIntoMinute =
                now.get(Calendar.SECOND) * 1000L + now.get(Calendar.MILLISECOND)
            // One second past the boundary so the widget reads the new state.
            return now.timeInMillis - secondsIntoMinute +
                soonestMinutes!! * 60_000L + 1_000L
        }

        private fun findNextClass(
            classes: List<ScheduledWidgetClass>,
            now: Calendar,
        ): NextWidgetClass? {
            if (classes.isEmpty()) return null

            val today = when (now.get(Calendar.DAY_OF_WEEK)) {
                Calendar.SUNDAY -> 7
                else -> now.get(Calendar.DAY_OF_WEEK) - 1
            }
            val nowMinutes =
                now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val millisIntoMinute =
                now.get(Calendar.SECOND) * 1000L + now.get(Calendar.MILLISECOND)
            val current = classes.firstOrNull {
                it.day == today &&
                    it.startMinutes <= nowMinutes &&
                    nowMinutes < it.endMinutes
            }
            if (current != null) {
                return NextWidgetClass(
                    item = current,
                    isHappeningNow = true,
                    millisToBoundary = (current.endMinutes - nowMinutes) * 60_000L -
                        millisIntoMinute,
                )
            }

            val next = classes.minByOrNull { item ->
                val dayDifference = (item.day - today + 7) % 7
                var minutesUntil =
                    dayDifference * 1440 + item.startMinutes - nowMinutes
                if (minutesUntil <= 0) minutesUntil += 7 * 1440
                minutesUntil
            }
            return next?.let { item ->
                val dayDifference = (item.day - today + 7) % 7
                var minutesUntil =
                    dayDifference * 1440 + item.startMinutes - nowMinutes
                if (minutesUntil <= 0) minutesUntil += 7 * 1440
                NextWidgetClass(
                    item = item,
                    isHappeningNow = false,
                    millisToBoundary = minutesUntil * 60_000L - millisIntoMinute,
                )
            }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            classes: List<ScheduledWidgetClass>,
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_next_class)
            val now = Calendar.getInstance()
            val today = when (now.get(Calendar.DAY_OF_WEEK)) {
                Calendar.SUNDAY -> 7
                else -> now.get(Calendar.DAY_OF_WEEK) - 1
            }
            val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

            val heightDp = manager
                .getAppWidgetOptions(appWidgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val compact = heightDp in 1 until FULL_LAYOUT_MIN_HEIGHT_DP
            val showDetails = heightDp == 0 || heightDp >= DETAILS_MIN_HEIGHT_DP
            applyPadding(context, views, compact)

            if (classes.isEmpty()) {
                views.setViewVisibility(R.id.widget_empty_container, View.VISIBLE)
                views.setViewVisibility(R.id.widget_active_container, View.GONE)
                views.setViewVisibility(R.id.widget_celebration_container, View.GONE)
            } else {
                val todayClasses = classes.filter { it.day == today }
                val allDoneForToday = todayClasses.isNotEmpty() && todayClasses.all { it.endMinutes <= nowMinutes }
                val isFreeDay = todayClasses.isEmpty()
                val isCelebration = allDoneForToday || isFreeDay
                val next = findNextClass(classes, now)

                if (isCelebration && next != null) {
                    views.setViewVisibility(R.id.widget_empty_container, View.GONE)
                    views.setViewVisibility(R.id.widget_active_container, View.GONE)
                    views.setViewVisibility(R.id.widget_celebration_container, View.VISIBLE)

                    if (allDoneForToday) {
                        views.setImageViewResource(
                            R.id.widget_celebration_icon,
                            R.drawable.next_class_widget_check_icon,
                        )
                        views.setTextViewText(
                            R.id.widget_celebration_title,
                            context.getString(R.string.next_class_widget_all_done_title),
                        )
                        views.setTextViewText(
                            R.id.widget_celebration_subtitle,
                            context.getString(R.string.next_class_widget_all_done_subtitle),
                        )
                    } else {
                        views.setImageViewResource(
                            R.id.widget_celebration_icon,
                            R.drawable.next_class_widget_sun_icon,
                        )
                        views.setTextViewText(
                            R.id.widget_celebration_title,
                            context.getString(R.string.next_class_widget_free_day_title),
                        )
                        views.setTextViewText(
                            R.id.widget_celebration_subtitle,
                            context.getString(R.string.next_class_widget_free_day_subtitle),
                        )
                    }
                    views.setViewVisibility(
                        R.id.widget_celebration_subtitle,
                        View.VISIBLE,
                    )

                    // Day pill badge
                    val dayDifference = (next.item.day - today + 7) % 7
                    val dayPill = if (dayDifference == 1) {
                        context.getString(R.string.next_class_widget_day_tomorrow)
                    } else {
                        when (next.item.day) {
                            1 -> "MONDAY"
                            2 -> "TUESDAY"
                            3 -> "WEDNESDAY"
                            4 -> "THURSDAY"
                            5 -> "FRIDAY"
                            6 -> "SATURDAY"
                            7 -> "SUNDAY"
                            else -> ""
                        }
                    }
                    views.setTextViewText(R.id.widget_shelf_day_pill, dayPill)

                    val countdownPrefix = context.getString(R.string.next_class_widget_starts_in)
                    val countdown = formatCountdown(next.millisToBoundary)
                    views.setTextViewText(
                        R.id.widget_shelf_when,
                        String.format(Locale.getDefault(), countdownPrefix, countdown),
                    )

                    views.setTextViewText(R.id.widget_shelf_subject, next.item.subject)
                    views.setTextViewText(
                        R.id.widget_shelf_time,
                        formatMinutes(next.item.startMinutes) +
                            " - " +
                            formatMinutes(next.item.endMinutes),
                    )

                    val room = next.item.room
                        .takeIf { it.isNotBlank() }
                        ?.let { formatRoom(it) }
                        .orEmpty()
                    val professor = next.item.professor
                        .takeIf {
                            it.isNotBlank() &&
                                !it.equals("Not specified", ignoreCase = true)
                        }
                        .orEmpty()
                    val hasDetails = room.isNotEmpty() || professor.isNotEmpty()

                    views.setTextViewText(R.id.widget_shelf_room, room)
                    views.setTextViewText(R.id.widget_shelf_professor, professor)
                    views.setViewVisibility(
                        R.id.widget_shelf_room_row,
                        if (room.isNotEmpty() && showDetails) View.VISIBLE else View.GONE,
                    )
                    views.setViewVisibility(
                        R.id.widget_shelf_professor_row,
                        if (professor.isNotEmpty() && showDetails) View.VISIBLE else View.GONE,
                    )
                    views.setViewVisibility(
                        R.id.widget_shelf_details,
                        if (hasDetails && showDetails) View.VISIBLE else View.GONE,
                    )
                } else if (next != null) {
                    views.setViewVisibility(R.id.widget_empty_container, View.GONE)
                    views.setViewVisibility(R.id.widget_active_container, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_celebration_container, View.GONE)

                    views.setTextViewText(
                        R.id.widget_label,
                        context.getString(
                            if (next.isHappeningNow) {
                                R.string.next_class_widget_in_class
                            } else {
                                R.string.next_class_widget_label
                            },
                        ),
                    )
                    val countdownPrefix = context.getString(
                        if (next.isHappeningNow) {
                            R.string.next_class_widget_ends_in
                        } else {
                            R.string.next_class_widget_starts_in
                        },
                    )
                    val countdown = formatCountdown(next.millisToBoundary)
                    views.setTextViewText(
                        R.id.widget_when,
                        String.format(Locale.getDefault(), countdownPrefix, countdown),
                    )
                    views.setTextViewText(R.id.widget_subject, next.item.subject)
                    views.setTextViewText(
                        R.id.widget_time,
                        formatMinutes(next.item.startMinutes) +
                            " - " +
                            formatMinutes(next.item.endMinutes),
                    )

                    val room = next.item.room
                        .takeIf { it.isNotBlank() }
                        ?.let { formatRoom(it) }
                        .orEmpty()
                    val professor = next.item.professor
                        .takeIf {
                            it.isNotBlank() &&
                                !it.equals("Not specified", ignoreCase = true)
                        }
                        .orEmpty()
                    val hasDetails = room.isNotEmpty() || professor.isNotEmpty()

                    views.setTextViewText(R.id.widget_room, room)
                    views.setTextViewText(R.id.widget_professor, professor)
                    views.setViewVisibility(
                        R.id.widget_room_row,
                        if (room.isNotEmpty() && showDetails) View.VISIBLE else View.GONE,
                    )
                    views.setViewVisibility(
                        R.id.widget_professor_row,
                        if (professor.isNotEmpty() && showDetails) View.VISIBLE else View.GONE,
                    )
                    views.setViewVisibility(
                        R.id.widget_details,
                        if (hasDetails && showDetails) View.VISIBLE else View.GONE,
                    )
                } else {
                    views.setViewVisibility(R.id.widget_empty_container, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_active_container, View.GONE)
                    views.setViewVisibility(R.id.widget_celebration_container, View.GONE)
                }
            }

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            manager.updateAppWidget(appWidgetId, views)
        }

        private fun formatMinutes(minutes: Int): String {
            val normalized = minutes.coerceIn(0, 1440)
            val hour24 = if (normalized == 1440) 24 else normalized / 60
            val hour12 = when {
                hour24 == 24 -> 12
                hour24 % 12 == 0 -> 12
                else -> hour24 % 12
            }
            val period = if (hour24 in 12..23) "PM" else "AM"
            return String.format(
                Locale.getDefault(),
                "%d:%02d %s",
                hour12,
                normalized % 60,
                period,
            )
        }

        private fun formatCountdown(millisToBoundary: Long): String {
            val minutes = ((millisToBoundary.coerceAtLeast(0L) + 59_999L) / 60_000L)
                .toInt()
            if (minutes < 60) return "$minutes min"

            val days = minutes / 1_440
            val hours = (minutes % 1_440) / 60
            val remainingMinutes = minutes % 60
            return when {
                days > 0 && hours > 0 && remainingMinutes > 0 ->
                    "${days}d ${hours}h ${remainingMinutes}m"
                days > 0 && hours > 0 -> "${days}d ${hours}h"
                days > 0 && remainingMinutes > 0 -> "${days}d ${remainingMinutes}m"
                days > 0 -> "${days}d"
                remainingMinutes > 0 -> "${hours}h ${remainingMinutes}m"
                else -> "${hours}h"
            }
        }

        private fun applyPadding(context: Context, views: RemoteViews, compact: Boolean) {
            val density = context.resources.displayMetrics.density
            val horizontal = (20 * density).toInt()
            val vertical = ((if (compact) 10 else 18) * density).toInt()
            views.setViewPadding(R.id.widget_root, horizontal, vertical, horizontal, vertical)
        }

        private fun formatRoom(room: String): String =
            if (Regex("[A-Za-z]{3,}").containsMatchIn(room)) room else "Room " + room

    }
}
