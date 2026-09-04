// Copyright 2019 Aleksander Woźniak
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../../services/auth_utility.dart';


import 'package:task_manager_admin_panel/utils/app_logger.dart';
/// Signature for a function that creates a widget for a given `day`.
typedef DayBuilder = Widget? Function(BuildContext context, DateTime day);

/// Signature for a function that creates a widget for a given `day`.
/// Additionally, contains the currently focused day.
typedef FocusedDayBuilder = Widget? Function(
    BuildContext context, DateTime day, DateTime focusedDay);

/// Signature for a function returning text that can be localized and formatted with `DateFormat`.
typedef TextFormatter = String Function(DateTime date, dynamic locale);

/// Gestures available for the calendar.
enum AvailableGestures { none, verticalSwipe, horizontalSwipe, all }

/// Formats that the calendar can display.
enum CalendarFormat { month, twoWeeks, week }

/// Days of the week that the calendar can start with.
enum StartingDayOfWeek {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

/// Returns a numerical value associated with given `weekday`.
///
/// Returns 1 for `StartingDayOfWeek.monday`, all the way to 7 for `StartingDayOfWeek.sunday`.
int getWeekdayNumber(StartingDayOfWeek weekday) {
  return StartingDayOfWeek.values.indexOf(weekday) + 1;
}

/// Returns `date` in UTC format, without its time part.
DateTime normalizeDate(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day);
}

/// Checks if two DateTime objects are the same day.
/// Returns `false` if either of them is null.
bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) {
    return false;
  }

  return a.year == b.year && a.month == b.month && a.day == b.day;
}

int? pegarEmpresaLogada() {
  final empresaId = AuthUtility.userInfo?.login?.empresa?.id;
  return (empresaId != null && empresaId != 0) ? empresaId : null;
}

int? pegarParceiroLogada() {
  final parceiroId = AuthUtility.userInfo?.login?.parceiro?.id;
  return (parceiroId != null && parceiroId != 0) ? parceiroId : null;
}

int? pegarUsuarioLogado() {
  final user = AuthUtility.userInfo?.login;
  final empresaId = user?.id;

  // Debug para verificar o que está retornando
  L.d('Usuário: ${AuthUtility.userInfo}');
  L.d('Empresa ID: $empresaId');

  // Retorna null se for 0 ou null
  return (empresaId != null && empresaId != 0) ? empresaId : null;
}

/// Extrai uma String de um campo JSON que pode ser String ou Map com campo 'nome'.
/// Útil para campos como cidade, estado, pais que o backend retorna como objeto.
String? jsonToString(dynamic value, {String nameField = 'nome'}) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map) return value[nameField]?.toString();
  return value.toString();
}
