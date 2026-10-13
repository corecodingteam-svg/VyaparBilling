# Design library

One visual language for the whole Flutter app. Colours come from the Moti Paper admin panel (violet primary, slate sidebar, soft grey page). Everything lives in `app/lib/shared/` — **a screen never hardcodes a colour, size, radius or font size**; if a value is missing, add a token here first.

## Tokens — `shared/design/tokens.dart`
| Group | Use |
|---|---|
| `AppColors` | `primary`, `sidebar*`, `background`, `surface`, `border*`, `text*`; money: `moneyIn` / `moneyOut`; status: `success*`, `warning*`, `danger*`, `info*`; `dangerStrong` for destructive fills |
| `AppSpace` | `xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 24 … huge 48` |
| `AppRadius` | `xs 4` checkboxes · `sm 6` tags · `md 8` buttons/inputs · `lg 10` cards/dialogs · `pill` |
| `AppFont` / `AppText` | `label 10 · caption 11 · small 12 · body 13 · bodyLarge 14 · subtitle 16 · title 17 · headline 22 · display 28 · hero 40`; ready styles `AppText.title`, `.subtitle`, `.helper`, `.error` … |
| `AppIconSize` | `sm · md · lg` |
| `AppSize` | control height 36, dialog widths (`dialogSm/Md/Lg/Xl/Form`), field widths, `listPane320`, `stateHeight260`, sidebar, breakpoints |
| `AppShadow`, `AppMotion` | elevation and animation durations/curves |

`buildTheme()` (`shared/theme.dart`) maps the tokens onto Material 3 component themes, so plain `FilledButton`, `TextField`, `Card`, `Chip`, `DataTable` etc. already look right. Don't restyle them locally.

## Buttons
Default `FilledButton` = primary (violet) for Add / Save. `OutlinedButton` = secondary. `AppButtons.tonal` = second action beside a primary. `AppButtons.destructive` / `destructiveOutlined` = **delete or remove only**. `AppButtons.compactIcon` for icon-only buttons in rows.

## Page and list building blocks
| Component | File | Use |
|---|---|---|
| `TitledPage` | `shared/page.dart` | Title, subtitle, action buttons, pull-to-refresh |
| `ListCubitView<T>` + `RowsCard` | `shared/page.dart` | Cubit-backed list: skeleton → rows (staggered fade-in) / empty / error |
| `ListRow` | `shared/widgets.dart` | One row with title, subtitle, trailing and actions that stays inside a phone width |
| `SectionCard`, `InfoField`, `DateField`, `StatusBadge` | `shared/widgets.dart` | Cards, read-only fields, dates, status pills |

## States (always these, never ad-hoc)
- **Loading** – `LoadingView()` (shimmer skeleton; `.spinner()` for dialogs), `InlineSpinner` inside buttons. Shimmer stops when the OS asks to reduce motion.
- **Empty** – `EmptyState(icon, title, message, action)`.
- **Error** – `ErrorRetry(error, onRetry)`.
- **Success / failure toast** – `showSuccess`, `showError`, `showInfo`.
- **Confirm delete** – `confirmDelete` (the only place `AppButtons.destructive` is filled).

## Motion — `shared/design/motion.dart`
`StateSwitcher` (cross-fade between loading / content / error), `FadeSlideIn(index)` (row entrance, one controller, no timers), `Reveal` (expand/collapse), page transitions in the theme.

## Pull to refresh — `shared/design/refresh.dart`
Wrap a scroll view in `PullToRefresh(onRefresh: …)`. `TitledPage` and `ListCubitView` do it for you. For a bloc: `context.reloadBloc<MyBloc, MyEvent, MyState>(const MyRequested())` waits for the reload to finish. Works with the mouse on desktop and web.

## Export and print — `shared/export.dart`
Every list page has an **Export** icon button (`ExportMenu`) offering *Export to Excel* (.xlsx, numbers stay numeric, header frozen) and *Print* (PDF table, repeating header, ₹ supported).
Add it to a new list page by describing the table the user sees:

```dart
ExportMenu(table: () => TableExport(
  title: 'Godowns',
  headers: ['Godown', 'Items', 'Stock value'],
  rows: [for (final g in godowns) [g.name, g.itemCount, g.stockValue]], // num stays a number
))
```
Reports use the same writer through `reportTable(data)` (`features/reports/report_format.dart`) and keep their own branded print preview.

## Forms and validation — `shared/design/validation.dart`
- `Validators` return plain-language messages: *"Email is required"*, *"Email must be a valid address, like name@example.com"*.
- Fields validate on interaction (`autovalidateMode.onUserInteraction`).
- On submit, `validateForm` finds the first failing field, scrolls to it, focuses it and shows a summary; cubit-driven forms expose `firstIssue()` and wrap fields in `FieldHighlight` so the offending element is outlined and the message sits beside it.

## Keyboard — `shared/design/keyboard_nav.dart`
`EnterKeyNavigation` sits above the Navigator (in `main.dart`), so **Enter moves to the next input on every screen, dialog and sheet** with no per-field code; Tab / Shift+Tab are Flutter's own. It leaves Enter alone in multiline fields, fields with their own `onSubmitted` (the submit action), search/send/go fields, buttons, dropdowns and autocompletes. Override an area with `EnterKeyBehavior(action: EnterKeyAction.next | submit | newline | ignore | automatic, child: …)`. The user can switch it off in Settings › Keyboard (`KeyboardNavCubit`, remembered per user on the device, on by default). Give a new search box `textInputAction: TextInputAction.search`.

## Sidebar, calendars, errors
- The wide sidebar collapses to an icon rail (`SidebarCubit`, remembered on the device); sections with pages open a menu from their icon.
- Dates: `DateField` (compact calendar dialog). Periods: `showCompactRangePicker` — never `showDateRangePicker`, which takes over the whole screen.
- Errors: everything goes through `ApiException.from`. Server messages and our own `FormatException`s are shown as written; other answers are explained by status; a program bug names its type and is logged. Never hardcode "Something went wrong".

## Rules
1. No `Color(0x…)`, `Colors.*`, numeric `fontSize`, `BorderRadius.circular(n)` or `EdgeInsets` magic numbers in `features/` (the PDF/print code is exempt: paper is not UI).
2. Reuse a component before writing a similar one; new patterns go in this file and `shared/`.
3. Every list page: skeleton while loading, `EmptyState`, `ErrorRetry`, pull-to-refresh, Export menu.
4. Check phone width (≈ 400 px) — `app/screenshots_test` renders desktop and phone for key screens.
