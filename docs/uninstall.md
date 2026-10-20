# Remove Lumen

This page shows you how to restore your TV's Home button, remove Lumen and its Mac helper, and revoke the helper's T3 Code session.

## Before you begin

- Keep the source directory available so you can run *`set-home.sh`* and *`mac/install.sh`*.
- On the TV, re-enable network debugging and [reconnect your computer](quickstart.md#turn-on-network-debugging-on-the-tv-and-connect). Verify that *`adb devices`* lists the TV with state *`device`*.
- Replace *`DEVICE_ADDRESS`* in this page with your TV's IP address and ADB port.
- For helper removal, use the Mac account that installed it. Keep T3 Code installed until you revoke the **Lumen TV** session. If you customized *`T3CODE_HOME`*, use that installation's *`bin/t3`* for session commands.

## Restore the Home button

Choose one launcher before uninstalling Lumen. Both script modes preserve unrelated accessibility services.

1. In the source directory, restore the stock Google TV home screen:

   ```sh
   ./set-home.sh stock DEVICE_ADDRESS
   ```

   This removes Lumen's and Projectivy's services from the enabled accessibility-service list and sends **Home**.

   Alternatively, if Projectivy is installed, make Projectivy Home:

   ```sh
   ./set-home.sh projectivy DEVICE_ADDRESS
   ```

   This enables Projectivy's package and accessibility service, removes Lumen's service, and sends **Home**.

2. On the remote, press **Home** to verify that your chosen launcher opens.

## Uninstall the TV app

> [!WARNING]
> Uninstalling deletes Lumen's private TV data: watch history, thumbnails, favorites, hidden apps, settings, pairing key and code, device ID, and saved Mac/helper details. It doesn't delete the Mac's pairing copy or revoke its T3 Code session.

1. On your computer, remove the app from the connected TV:

   ```sh
   adb -s DEVICE_ADDRESS uninstall local.tvhome
   ```

## Remove Lumen Agents

Choose whether to retain the helper's data. Neither option revokes the T3 Code session on the T3 Code side.

1. In the source directory on your Mac, remove the helper but retain its token, pairings, helper ID, admin secret, and log:

   ```sh
   ./mac/install.sh uninstall
   ```

   This stops *`local.lumen.agents`* and removes its launchd file, binary, and *`~/.local/bin/lumen-agents`* link.

   > [!WARNING]
   > Purging also deletes *`~/Library/Application Support/Lumen Agents`* and *`~/Library/Logs/lumen-agents.log`*, including the saved token, pairing keys, helper ID, and admin secret. Pairings can't be restored without their keys. Use this alternative only if you want that data deleted.

   To delete the retained data as well, use this command instead, or after uninstalling:

   ```sh
   ./mac/install.sh purge
   ```

## Revoke the T3 Code session

These commands and their output were verified with T3 Code (Beta) 0.1.0.

1. On your Mac, list T3 Code sessions:

   ```sh
   ~/.t3/bin/t3 auth session list
   ```

   For a custom *`T3CODE_HOME`*, use that directory's *`bin/t3`* instead.

2. In the session list, find the block with *`client: Lumen TV | bot`*. Each block starts with the session ID on its own line, followed by metadata such as *`client:`*, *`issued:`*, and *`expires:`*. Note the ID from the first line. If there are multiple **Lumen TV** sessions from renewals or reinstalls, repeat revocation for each you want to remove.
3. On your Mac, revoke the session:

   ```sh
   ~/.t3/bin/t3 auth session revoke SESSION_ID
   ```

   Replace *`SESSION_ID`* with the ID from the session list. A successful revocation prints *`Revoked session SESSION_ID.`*, with your session ID in place of *`SESSION_ID`*.

## Verify removal

Complete the TV checks before turning network debugging off.

1. On the remote, press **Home**. Your chosen launcher opens.
2. On your computer, check whether the TV package remains:

   ```sh
   adb -s DEVICE_ADDRESS shell pm path local.tvhome
   ```

   No APK path should be returned for Lumen.

3. On your Mac, check the helper's launchd job:

   ```sh
   launchctl print "gui/$(id -u)/local.lumen.agents"
   ```

   The job should no longer be found.

4. On your Mac, list T3 Code sessions again to verify the selected session is no longer active:

   ```sh
   ~/.t3/bin/t3 auth session list
   ```

5. In the TV's developer options, verify that network debugging is off after completing the TV checks.

## Recover without ADB

The Lumen accessibility service is labeled **Lumen**. You can turn it off through the TV's accessibility settings; manufacturer menu names and nesting vary. The service doesn't block other remote keys or the system settings screen.

1. In Lumen, select **Settings > TV settings** to open the TV's system settings. If Lumen isn't usable, use your remote's system-settings shortcut if it has one.
2. In the TV's system settings, find **Accessibility**. It can be nested under another settings category, depending on the TV.
3. In the accessibility-service list, select **Lumen**.
4. In the service's controls, turn Lumen off.
5. On the remote, press **Home** to check that the stock launcher, or another launcher you configured, opens.

Google TV may ignore the normal default-home choice, so this procedure removes Lumen's interception rather than relying on a launcher picker. If you still can't reach system settings or recover the launcher, consult your TV manufacturer's recovery instructions. A factory reset is a last resort and deletes TV data and settings; this guide doesn't prescribe a reset procedure.

## What's next

- [Review which data removal affects](../PRIVACY.md#remove-stored-data).
- [Report the problem that led to removal](../CONTRIBUTING.md#report-a-bug).
