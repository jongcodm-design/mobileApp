class ScheduleTextDetails {
  const ScheduleTextDetails({
    required this.subject,
    required this.room,
    required this.professor,
  });

  final String subject;
  final String room;
  final String professor;

  static final RegExp _roomPattern = RegExp(
    r'\b(?:Room|Rm\.?)\s*[-:#]?\s*[A-Za-z0-9-]+|\b(?:Lab|Laboratory)\s*[-:#]?\s*(?:[A-Z]{1,3}\s*[-]?\s*)?\d+[A-Z]?\b|\b(?:NetLab|MacLab)\b|(?<!\d)[RL]\s*[-]?\s*\d{1,2}[A-Z]?',
    caseSensitive: false,
  );
  static final RegExp _professorLinePattern = RegExp(
    r"(?:^|\s)([A-Z](?:\.|\s+)\s*(?:[A-Z][a-z]+(?:[A-Z][a-z]+)?|[A-Z]{3,}(?:[-'][A-Z]{2,})?)(?:\s+[A-Z][a-z]+)?)\s*$",
  );
  static final RegExp _singleLetterRoomPattern = RegExp(
    r'^(?:Room|Rm\.?)\s*[-:#]?\s*([A-Z])$',
    caseSensitive: false,
  );
  static final RegExp _orphanedProfessorSurnamePattern = RegExp(
    r"^[.,;:]?\s*([A-Z][a-z]+(?:[A-Z][a-z]+)?(?:\s+[A-Z][a-z]+)?|[A-Z]{3,}(?:[-'][A-Z]{2,})?)\s*$",  );

  factory ScheduleTextDetails.parse(String text) =>
      ScheduleTextDetails.parseLines([text]);

  static String _collapseRepeatedPhrases(String text) {
    final words = text.split(RegExp(r'\s+'));
    var changed = true;
    while (changed && words.length >= 4) {
      changed = false;
      for (
        var phraseLength = words.length ~/ 2;
        phraseLength >= 2 && !changed;
        phraseLength--
      ) {
        for (var start = 0; start + phraseLength * 2 <= words.length; start++) {
          var similarity = 0.0;
          for (var offset = 0; offset < phraseLength; offset++) {
            final first = words[start + offset].toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            );
            final second = words[start + phraseLength + offset]
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]'), '');
            if (first.isEmpty || second.isEmpty) continue;
            final distance = _editDistance(first, second);
            similarity +=
                1 -
                distance /
                    (first.length > second.length
                        ? first.length
                        : second.length);
          }
          if (similarity / phraseLength < .8) continue;
          words.removeRange(start + phraseLength, start + phraseLength * 2);
          changed = true;
          break;
        }
      }
    }
    return words.join(' ');
  }

  static int _editDistance(String first, String second) {
    var previous = List<int>.generate(second.length + 1, (i) => i);
    for (var i = 0; i < first.length; i++) {
      final current = List<int>.filled(second.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < second.length; j++) {
        final substitutionCost = first[i] == second[j] ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + substitutionCost,
        ].reduce((a, b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous.last;
  }

  static String _removeProfessorSuffix(
    String subject,
    Iterable<String> professors,
  ) {
    var cleaned = subject;
    for (final professor in professors) {
      final nameParts = professor
          .split(RegExp(r'[\s.]+'))
          .where((part) => part.isNotEmpty)
          .map(RegExp.escape)
          .toList();
      if (nameParts.isEmpty) continue;
      final namePattern = nameParts.join(r'[\s.]*');
      cleaned = cleaned.replaceFirst(
        RegExp('(?:^|\\s)$namePattern\\.?\\s*\$', caseSensitive: false),
        '',
      );
    }
    return cleaned
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[|,; -]+|[|,; -]+$'), '')
        .trim();
  }

  factory ScheduleTextDetails.parseLines(Iterable<String> lines) {
    final subjects = <String>[];
    final rooms = <String>[];
    final professors = <String>[];
    final normalizedLines = lines
        .map(
          (line) =>
              line.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList();
    for (var i = 0; i < normalizedLines.length; i++) {
      var normalized = normalizedLines[i];
      if (RegExp(
            r'^(?:Room|Rm\.?|Lab|Laboratory)$',
            caseSensitive: false,
          ).hasMatch(normalized) &&
          i + 1 < normalizedLines.length &&
          RegExp(
            r'^(?:[A-Z]{1,3}\s*[-]?\s*)?\d+[A-Z]?$',
            caseSensitive: false,
          ).hasMatch(normalizedLines[i + 1])) {
        normalized = '$normalized ${normalizedLines[++i]}';
      }

      final roomMatch = _roomPattern.firstMatch(normalized);
      var remainder = normalized;
      if (roomMatch != null) {
        final roomText = roomMatch
            .group(0)!
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final singleLetterRoom = _singleLetterRoomPattern.firstMatch(roomText);
        final trailingText = normalized.substring(roomMatch.end).trim();
        final orphanedSurname = singleLetterRoom == null
            ? null
            : _orphanedProfessorSurnamePattern.firstMatch(trailingText);

        // OCR can mistake the professor's initial for the room code, leaving
        // only the surname after the room token (for example, "Room R .Tiongco").
        // Recover the instructor and flag the room for review instead of saving
        // the initial as a confidently parsed room.
        if (singleLetterRoom != null && orphanedSurname != null) {
          professors.add(
            '${singleLetterRoom.group(1)!.toUpperCase()}. ${orphanedSurname.group(1)!.trim()}',
          );
          rooms.add('Room to confirm');
          remainder = normalized.substring(0, roomMatch.start);
        } else {
          rooms.add(roomText);
          remainder = normalized.replaceRange(
            roomMatch.start,
            roomMatch.end,
            ' ',
          );
        }
      }

      final professorMatch = _professorLinePattern.firstMatch(remainder);
      if (professorMatch != null) {
        professors.add(professorMatch.group(1)!.trim());
        remainder = remainder.substring(0, professorMatch.start);
      }
      final subject = remainder
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'^[|,; -]+|[|,; -]+$'), '')
          .replaceAll(RegExp(r'\biT\b'), 'IT')
          .trim();
      if (subject.isNotEmpty) subjects.add(subject);
    }
    final subject = _removeProfessorSuffix(
      subjects.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
      professors,
    );
    return ScheduleTextDetails(
      subject: _collapseRepeatedPhrases(subject),
      room: rooms.isEmpty ? 'Room to confirm' : rooms.first,
      professor: professors.isEmpty ? 'Not specified' : professors.first,
    );
  }
}
