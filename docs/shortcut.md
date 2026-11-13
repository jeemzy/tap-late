# iPhone Shortcut

Use the same private server address at home and away when possible, for example `http://10.8.0.2:8000` through your existing WireGuard routing. This example address is a placeholder, not a discovered address for your PC.

First, open that address in Safari. If it cannot load, fix Wi-Fi/VPN routing to the PC before configuring the Shortcut. The app does not create WireGuard peers or change Windows firewall rules.

On the same Wi-Fi, this installation also advertises `http://tap-late.local:8000`. Use that as `Server` when the Windows mDNS helper is running; the numeric Wi-Fi address is a fallback. `.local` discovery is limited to the local network and is not a WireGuard DNS configuration. The README describes the optional logon helper and the scoped Windows/WSL firewall rules.

## Build the Shortcut

Create a Shortcut named **tap-late** with these actions:

1. **Text:** enter the server base address, without a trailing slash. Set a variable called `Server` to it.
2. **Take Screenshot.** Keep its output as `Screenshot`.
3. **Convert Image:** convert `Screenshot` to PNG. This ensures a supported file type.
4. **Generate UUID:** keep the result as `Session ID`. This action is supplied by the free [Actions app](https://sindresorhus.com/actions) if your installed action list does not already provide it.
5. **Get Contents of URL:** use `Server` followed by `/api/sessions`. Expand its options:
   - Method: **POST**.
   - Request Body: **Form**.
   - Add a **File** field named `file`, using the converted PNG.
   - Add a **Text** field named `session_id`, using `Session ID`.
   - Let Shortcuts set the multipart Content-Type and boundary; do not add a Content-Type header manually.
6. **Get Dictionary Value:** get `view_url` from the upload response.
7. **Text:** combine `Server` and `view_url` directly. The latter begins with `/view/`.
8. **Open URLs:** open the combined URL.

The upload returns before OCR/translation finishes. Safari shows the screenshot and progress, then the translated regions. Repeating an upload with the same UUID and PNG returns the existing session.

If you prefer only built-in actions, omit UUID generation and the `session_id` form field: the backend generates a UUID and returns the same viewer URL structure. The client-generated UUID path above preserves the originally requested workflow; server generation is also supported.

## Assign the trigger

- **Back Tap:** Settings → Accessibility → Touch → Back Tap → Double Tap or Triple Tap → select **tap-late**.
- **Action Button:** Settings → Action Button → Shortcut → select **tap-late** (on a supported iPhone).

Allow requested screenshot, local-network and server access when iOS prompts. The Shortcut does not need your OpenAI key. A first-run permission prompt is native iOS behavior, not an app approval step.

## If something fails

- **Cannot connect:** verify WireGuard is connected when away, the PC is awake, Docker is running, and Safari can open the server address. WireGuard routing must include the PC's reachable address/port.
- **Upload error:** check the response's `detail`; use the exact form field names above and a PNG file.
- **UUID conflict:** generate a fresh UUID for a new capture. Reuse a UUID only to retry the same image.
- **Translation failed:** the viewer explains the problem and offers retry. Check the server's OpenAI key, model access, credits and outbound connection.
- **Expired/deleted URL:** capture and upload again. Sessions normally last seven days.

The app cannot wake a sleeping PC. Actual Back Tap/Action Button timing and your private VPN route need verification on your own iPhone.

References: [Apple's POST request guide](https://support.apple.com/en-euro/guide/shortcuts/apd58d46713f/ios), [Apple's Back Tap guide](https://support.apple.com/en-gb/guide/shortcuts/apd897693606/ios), [Actions app and UUID action](https://sindresorhus.com/actions).
