# Working on the app from a Windows PC

How to get the billing app's code onto a Windows PC, build it, and run it against the live server
(`billing.advaitamaa.com`). The Tally connector will be built and tested this way, because TallyPrime only runs on Windows.

## 1. Install the tools

- **Git for Windows**: https://git-scm.com/download/win
- **Flutter 3.47.5** (the version the CI builds with; see `FLUTTER_VERSION` in `.github/workflows/build-apps.yml`):
  https://docs.flutter.dev/get-started/install/windows. Add its `bin` folder to `PATH`.
- **Visual Studio 2022** (Community is free), with the **Desktop development with C++** workload. Flutter needs it to
  build Windows apps. Visual Studio Code is not enough on its own.

Then check everything is found:

```powershell
flutter doctor
```

The Windows lines must show a tick. Android and Chrome are only needed if you build for them too.

## 2. Get the code

```powershell
git clone https://github.com/corecodingteam-svg/VyaparBilling.git
cd VyaparBilling\app
flutter pub get
```

## 3. Run the app

Build it the same way the CI does, adding the server address:

```powershell
flutter run -d windows --dart-define=API_BASE_URL=https://billing.advaitamaa.com/api/v1
```

Without `--dart-define=API_BASE_URL=…` the app looks for a backend on `http://localhost:3100`, which is only there if you run
the backend on the same PC (see the top-level `README.md`).

**The licence key.** The CI also passes `--dart-define=LICENSE_PUBLIC_KEY=…`, the public key the live server signs licences
with (repository variable `LICENSE_PUBLIC_KEY` on GitHub, or `BILLING_LICENSE_PUBLIC_KEY` in the server's `deploy/.env`).
Without it the app uses the development key built into the code. If that differs from the server's, business logins stop at
the licence screen. Add the same `--dart-define=LICENSE_PUBLIC_KEY=<key>` to the command to avoid that. The master admin
login (`/#/master` on the web; the Master admin sign-in in the app) needs no licence.

To build an installable copy instead of running from the code:

```powershell
flutter build windows --release --dart-define=API_BASE_URL=https://billing.advaitamaa.com/api/v1
```

The app is then in `build\windows\x64\runner\Release\`. The CI also makes `Billing-Setup.exe` from it with Inno Setup
(`windows/installer/billing.iss`).

## 4. If the app says it cannot reach the server

Check the site first: open https://billing.advaitamaa.com in a browser. If that does not load either, the problem is the
server, not the app. The server is the Hostinger VPS **srv2005150** (72.60.40.159), which also runs advaitamaa.com.

On 17 October 2026 it stopped answering on every port, although Hostinger showed it as running. It needs a restart from
hPanel (VPS › srv2005150 › Restart) before the app can connect. Every site on it comes back together.

## 5. Before committing

```powershell
flutter analyze
flutter test
```

Both must pass. Pushing to `main` runs the same checks on GitHub and builds the Android and Windows apps.

## Next: the Tally connector

The plan is to read TallyPrime's built-in XML server (port 9000) from the Windows app, the way LiveKeeping's Data Connector
does (setup video: `docs/tally/`). On the same PC:

1. Install TallyPrime. Educational mode (free, no licence) is enough for testing; it only takes vouchers dated the 1st, the
   2nd or the last day of a month.
2. Make a test company with customers, suppliers, stock items with GST, some sales, purchases and receipts, and unpaid bills.
3. In TallyPrime press **F1 (Help) › Settings › Connectivity**, set **TallyPrime acts as** to **Both** and the port to
   **9000**. Allow it when Windows Firewall asks.
4. Check it answers: open http://localhost:9000 in a browser. It should reply "TallyPrime Server is Running".

Still to decide: a one-time import of a company (customers, suppliers, items, opening balances, unpaid bills) or ongoing sync
like LiveKeeping's. What the file import does today is in `docs/TALLY-INTEGRATION-TEST-MANUAL.md`.
