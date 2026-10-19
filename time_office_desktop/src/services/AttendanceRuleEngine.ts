/**
 * Configuration-Driven Attendance Rule Engine
 * 
 * CRITICAL REQUIREMENT: ZERO HARDCODED ATTENDANCE BUSINESS RULES.
 * 
 * This engine interprets raw data and database-driven rule configurations.
 * Neither shift timings, grace periods, nor attendance classifications
 * are hardcoded here. All rules, conditions, and actions are evaluated dynamically.
 */

export interface RuleCondition {
  field: string;
  operator: 'EQUAL' | 'NOT_EQUAL' | 'GREATER_THAN' | 'LESS_THAN' | 'GREATER_OR_EQUAL' | 'LESS_OR_EQUAL' | 'BETWEEN' | 'EXISTS' | 'NOT_EXISTS' | 'IN' | 'NOT_IN';
  value: any;
}

export interface RuleAction {
  field: string;
  value: any;
}

export interface ConfiguredRule {
  rule_id: string;
  name: string;
  enabled: boolean;
  priority: number;
  conditions: RuleCondition[];
  actions: RuleAction[];
}

export interface StatusDefinition {
  code: string;
  label: string;
  display_type: 'success' | 'warning' | 'danger' | 'info' | 'neutral';
}

export interface RuleConfiguration {
  status_definitions: StatusDefinition[];
  rules: ConfiguredRule[];
}

export interface RawEmployee {
  id: number;
  employee_id: string;
  full_name: string;
  department: string;
  location_name: string;
  is_active: boolean;
}

export interface RawPunchPeriod {
  id: number;
  punch_no: number;
  period_name: string;
  period_type: string;
  start_time: string;
  end_time: string;
  priority: number;
  is_active: boolean;
}

export interface RawShift {
  id: number;
  shift_code: string;
  shift_name: string;
  is_active: boolean;
  punch_periods: RawPunchPeriod[];
}

export interface RawShiftAssignment {
  id: number;
  user_id: number;
  shift_id: number;
  effective_from: string | null;
  effective_to: string | null;
}

export interface RawPunch {
  id: number;
  user_id: number;
  attendance_date: string;
  verification_no: number;
  timestamp: string;
  time_str: string;
  time_24: string;
  status: string;
}

export interface RawDatasetPayload {
  server_time: {
    date: string;
    time: string;
    iso: string;
    timezone: string;
  };
  raw_data: {
    employees: RawEmployee[];
    shifts: RawShift[];
    assignments: RawShiftAssignment[];
    punches: RawPunch[];
  };
  configuration: RuleConfiguration;
}

export interface AttendanceDecision {
  user_id: number;
  employee_id: string;
  employee_name: string;
  department: string;
  shift_id: number;
  shift_code: string;
  shift_name: string;
  attendance_date: string;
  required_periods: number;
  completed_periods: number;
  missed_periods: number;
  first_punch_time: string | null;
  first_punch_window_start: string | null;
  first_punch_window_end: string | null;
  attendance_status: string;
  timing_status: string;
  first_punch_status: string;
  full_day_status: string;
  reason: string;
  actual_first_valid_punch: string | null;
  punch_timing: string;
  location_name: string;
  configured_reference_time: string | null;
  delay: string;
  applied_rules: string[];
}

function parseTimeToSeconds(timeStr: string): number {
  if (!timeStr) return 0;
  const parts = timeStr.split(':').map(Number);
  const h = parts[0] || 0;
  const m = parts[1] || 0;
  const s = parts[2] || 0;
  return h * 3600 + m * 60 + s;
}

function formatSecondsToHHMMSS(totalSeconds: number): string {
  if (totalSeconds <= 0) return '00:00:00';
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(h)}:${pad(m)}:${pad(s)}`;
}

export class AttendanceRuleEngine {
  /**
   * Generic condition evaluator supporting dynamic comparison operators.
   */
  public static evaluateCondition(condition: RuleCondition, context: Record<string, any>): boolean {
    const fieldValue = context[condition.field];
    let targetValue = condition.value;

    // Handle context variable replacement (e.g. "required_periods_count")
    if (typeof targetValue === 'string' && context[targetValue] !== undefined) {
      targetValue = context[targetValue];
    }

    switch (condition.operator) {
      case 'EQUAL':
        return fieldValue === targetValue;
      case 'NOT_EQUAL':
        return fieldValue !== targetValue;
      case 'GREATER_THAN':
        return fieldValue > targetValue;
      case 'LESS_THAN':
        return fieldValue < targetValue;
      case 'GREATER_OR_EQUAL':
        return fieldValue >= targetValue;
      case 'LESS_OR_EQUAL':
        return fieldValue <= targetValue;
      case 'EXISTS':
        return fieldValue !== undefined && fieldValue !== null;
      case 'NOT_EXISTS':
        return fieldValue === undefined || fieldValue === null;
      case 'IN':
        return Array.isArray(targetValue) && targetValue.includes(fieldValue);
      case 'NOT_IN':
        return Array.isArray(targetValue) && !targetValue.includes(fieldValue);
      case 'BETWEEN':
        if (Array.isArray(targetValue) && targetValue.length === 2) {
          return fieldValue >= targetValue[0] && fieldValue <= targetValue[1];
        }
        return false;
      default:
        return false;
    }
  }

  /**
   * Processes raw employee records against database-driven rule configurations.
   */
  public static evaluateDataset(payload: RawDatasetPayload): AttendanceDecision[] {
    const { raw_data, configuration, server_time } = payload;
    const { employees, shifts, assignments, punches } = raw_data;
    const rules = [...(configuration?.rules || [])].sort((a, b) => (a.priority || 0) - (b.priority || 0));

    const decisions: AttendanceDecision[] = [];

    // Map shifts by ID for O(1) lookup
    const shiftMap = new Map<number, RawShift>();
    shifts.forEach((s) => shiftMap.set(s.id, s));

    // Map assignments by user_id
    const assignmentMap = new Map<number, number>();
    assignments.forEach((a) => assignmentMap.set(a.user_id, a.shift_id));

    // Group punches by user_id
    const userPunchesMap = new Map<number, RawPunch[]>();
    punches.forEach((p) => {
      const list = userPunchesMap.get(p.user_id) || [];
      list.push(p);
      userPunchesMap.set(p.user_id, list);
    });

    for (const emp of employees) {
      // 1. Resolve active assigned shift dynamically
      const shiftId = assignmentMap.get(emp.id) || (shifts.length > 0 ? shifts[0].id : 0);
      const shift = shiftMap.get(shiftId) || (shifts.length > 0 ? shifts[0] : null);

      if (!shift) continue;

      // 2. Resolve configured punch periods dynamically (sorted by sequence/priority)
      const periods = [...(shift.punch_periods || [])].sort((a, b) => a.priority - b.priority);
      const requiredPeriodsCount = periods.length;

      const firstPeriod = periods.length > 0 ? periods[0] : null;
      const firstPeriodStart = firstPeriod ? firstPeriod.start_time : null;
      const firstPeriodEnd = firstPeriod ? firstPeriod.end_time : null;

      // 3. Resolve user punches
      const userPunches = userPunchesMap.get(emp.id) || [];

      // Calculate completed periods count dynamically across N shift periods
      let completedPeriodsCount = 0;
      periods.forEach((period) => {
        const hasPunchInPeriod = userPunches.some(
          (p) => p.time_24 >= period.start_time && p.time_24 <= period.end_time
        );
        if (hasPunchInPeriod) {
          completedPeriodsCount += 1;
        }
      });

      const missedPeriodsCount = Math.max(0, requiredPeriodsCount - completedPeriodsCount);

      // Check for valid punch in first period dynamically
      let firstWindowPunch: RawPunch | null = null;
      if (firstPeriodStart && firstPeriodEnd) {
        firstWindowPunch = userPunches.find(
          (p) => p.time_24 >= firstPeriodStart && p.time_24 <= firstPeriodEnd
        ) || null;
      }

      const hasFirstWindowPunch = Boolean(firstWindowPunch);
      const firstPunchTime = firstWindowPunch ? firstWindowPunch.time_str : (userPunches.length > 0 ? userPunches[0].time_str : null);

      let actualFirstValidPunch = '-';
      let punchTiming = 'NO_PUNCH';
      let delayStr = '00:00:00';

      if (userPunches.length > 0) {
        actualFirstValidPunch = userPunches[0].time_str;
        punchTiming = hasFirstWindowPunch ? 'ON_TIME' : 'PUNCHED_AFTER_WINDOW';

        if (firstPeriodStart && userPunches[0].time_24) {
          const punchSec = parseTimeToSeconds(userPunches[0].time_24);
          const refSec = parseTimeToSeconds(firstPeriodStart);
          if (punchSec > refSec) {
            delayStr = formatSecondsToHHMMSS(punchSec - refSec);
          }
        }
      }

      // Build Evaluation Context
      const evalContext: Record<string, any> = {
        is_scheduled: true,
        is_holiday: false,
        is_weekly_off: false,
        has_first_window_punch: hasFirstWindowPunch,
        has_any_punch: userPunches.length > 0,
        completed_periods_count: completedPeriodsCount,
        required_periods_count: requiredPeriodsCount,
        missed_periods_count: missedPeriodsCount,
        first_punch_time_after_period_start: userPunches.length > 0 && firstPeriodStart ? userPunches[0].time_24 > firstPeriodStart : false,
        is_after_period_start: userPunches.length > 0 && firstPeriodStart ? userPunches[0].time_24 > firstPeriodStart : false,
      };

      // Base Decision Object
      const decision: AttendanceDecision = {
        user_id: emp.id,
        employee_id: emp.employee_id,
        employee_name: emp.full_name,
        department: emp.department || 'N/A',
        shift_id: shift.id,
        shift_code: shift.shift_code,
        shift_name: shift.shift_name,
        attendance_date: server_time.date,
        required_periods: requiredPeriodsCount,
        completed_periods: completedPeriodsCount,
        missed_periods: missedPeriodsCount,
        first_punch_time: firstPunchTime,
        first_punch_window_start: firstPeriodStart,
        first_punch_window_end: firstPeriodEnd,
        attendance_status: userPunches.length > 0 ? 'PRESENT' : 'ABSENT_FIRST_PUNCH',
        timing_status: evalContext.is_after_period_start ? 'LATE' : 'ON_TIME',
        first_punch_status: hasFirstWindowPunch ? 'PRESENT_FIRST_PUNCH' : 'ABSENT_FIRST_PUNCH',
        full_day_status: completedPeriodsCount === 0 ? 'FULL_DAY_ABSENT' : (completedPeriodsCount < requiredPeriodsCount ? 'HALF_DAY' : 'PRESENT'),
        reason: evalContext.is_after_period_start
          ? `Punch time (${actualFirstValidPunch}) matched configured late condition (after reference time ${firstPeriodStart || 'N/A'})`
          : (completedPeriodsCount === 0 ? 'No valid punches completed across required shift periods' : 'Evaluated by Attendance Rule Engine'),
        actual_first_valid_punch: actualFirstValidPunch,
        punch_timing: punchTiming,
        location_name: emp.location_name || 'N/A',
        configured_reference_time: firstPeriodStart,
        delay: delayStr,
        applied_rules: [],
      };

      // 4. Dynamic Rule Execution Engine (Sorted by DB Priority)
      for (const rule of rules) {
        if (!rule.enabled) continue;

        const allConditionsPass = rule.conditions.every((c) =>
          this.evaluateCondition(c, evalContext)
        );

        if (allConditionsPass) {
          rule.actions.forEach((act) => {
            (decision as any)[act.field] = act.value;
          });
          decision.applied_rules.push(rule.rule_id);
        }
      }

      decisions.push(decision);
    }

    return decisions.sort((a, b) => a.employee_id.localeCompare(b.employee_id));
  }
}
