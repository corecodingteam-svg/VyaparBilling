/** Provider staff who may manage every business: the emails in PLATFORM_ADMIN_EMAILS (comma separated). Empty = nobody. */
export function isPlatformAdmin(email: string, env: string | undefined = process.env.PLATFORM_ADMIN_EMAILS): boolean {
  return (env ?? '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean)
    .includes(email.trim().toLowerCase());
}
