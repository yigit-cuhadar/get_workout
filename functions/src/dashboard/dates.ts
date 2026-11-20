/** Days are `YYYY-MM-DD` strings, counted in UTC so no clock shifts them. */

const DAY_MS = 24 * 60 * 60 * 1000;
const DAY = /^(\d{4})-(\d{2})-(\d{2})$/;

/** An inclusive range of days. */
export interface DayRange {
  from: string;
  to: string;
}

/** Whether [value] is a real calendar day as `YYYY-MM-DD`. */
export const isDay = (value: unknown): value is string => {
  if (typeof value !== "string" || !DAY.test(value)) return false;
  const time = Date.parse(`${value}T00:00:00Z`);
  return !Number.isNaN(time) && new Date(time).toISOString().startsWith(value);
};

const toMillis = (day: string) => Date.parse(`${day}T00:00:00Z`);
const fromMillis = (millis: number) =>
  new Date(millis).toISOString().slice(0, 10);

export const addDays = (day: string, days: number) =>
  fromMillis(toMillis(day) + days * DAY_MS);

/** The number of days in [range], both ends included. */
export const lengthOf = ({ from, to }: DayRange) =>
  Math.round((toMillis(to) - toMillis(from)) / DAY_MS) + 1;

/** Every day of [range], in order. */
export const daysOf = (range: DayRange): string[] =>
  Array.from({ length: lengthOf(range) }, (_, i) => addDays(range.from, i));

/** The equally long range just before [range]. */
export const previousOf = (range: DayRange): DayRange => ({
  from: addDays(range.from, -lengthOf(range)),
  to: addDays(range.from, -1),
});

/** The [days] days ending at [to]. */
export const endingAt = (to: string, days: number): DayRange => ({
  from: addDays(to, 1 - days),
  to,
});

/** `YYYYMMDD`, the suffix of the day's `events_` table. */
export const suffixOf = (day: string) => day.replaceAll("-", "");

/** The Monday of [day]'s week. */
export const mondayOf = (day: string) => {
  const weekday = new Date(toMillis(day)).getUTCDay();
  return addDays(day, -((weekday + 6) % 7));
};

/** The day in [timeZone] at [millis]. */
export const dayAt = (millis: number, timeZone: string) =>
  new Intl.DateTimeFormat("en-CA", { timeZone }).format(new Date(millis));
