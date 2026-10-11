/** Converts pg numeric strings to JS numbers for API responses (null stays null). */
export const num = (v: string | number | null | undefined): number | null =>
  v === null || v === undefined ? null : Number(v);

/**
 * Today's date where the business is, as 'YYYY-MM-DD'. The server's own clock is usually UTC, which
 * is still "yesterday" in India until 5:30 in the morning.
 */
export const today = (): string =>
  new Intl.DateTimeFormat('en-CA', { timeZone: process.env.BUSINESS_TIMEZONE ?? 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
