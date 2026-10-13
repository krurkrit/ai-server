# Option: Custom login page

Part of [Step 6: Dex](../ai-server-setup-guide.md#step-6-dex-sign-in). Dex's `compose.yaml` and `config.yaml` already contain the lines below, commented out.

## Name, logo, and the Inter font

Dex's sign-in page can carry your own name, logo, and font. The page is built from a folder of templates and a theme; you copy Dex's own folder once, change the copy, and point Dex at it.

1. Copy the default page files out of the running Dex image, and start a theme from the light one:
   ```bash
   docker cp dex:/srv/dex/web /opt/stacks/dex/web
   cp -r /opt/stacks/dex/web/themes/light /opt/stacks/dex/web/themes/custom
   ```
2. Add the Inter font. The file is stored in the theme folder, so browsers load it from this server, not from the internet:
   ```bash
   curl -fL -o /opt/stacks/dex/web/themes/custom/InterVariable.woff2 https://rsms.me/inter/font-files/InterVariable.woff2
   cat >> /opt/stacks/dex/web/themes/custom/styles.css <<'EOF'

   /* Inter, served from this theme folder */
   @font-face {
     font-family: "Inter";
     src: url("InterVariable.woff2") format("woff2");
     font-weight: 100 900;
     font-display: swap;
   }
   .theme-body {
     font-family: "Inter", system-ui, sans-serif;
   }
   EOF
   ```
   Buttons and inputs inherit the page font, so this one rule covers the whole page.
3. Optional: replace `themes/custom/logo.png` (shown top left, about 26px high) and `themes/custom/favicon.png` with your own PNGs, and change other colors in `themes/custom/styles.css`. Text and layout live in `templates/*.html` (e.g. `password.html` for the password form); edit them only if needed.
4. Turn it on: in `compose.yaml`, uncomment the `./web:/srv/dex/web-custom:ro` line; in `config.yaml`, uncomment the `frontend:` block and set `issuer` to the name to show. Then:
   ```bash
   cd /opt/stacks/dex && docker compose up -d --force-recreate dex
   ```
5. Open any app's "Sign in with Dex" (or a gated app) and reload with Ctrl+Shift+R. Dex serves the theme at `https://<SERVER_HOST>:5556/dex/theme/styles.css`; if the page looks unstyled, `docker logs dex` names the file it can't read.

## Custom HTML templates

The page text and layout are Go HTML templates in `/opt/stacks/dex/web/templates/`. Keep an untouched copy first, so a mistake is easy to undo:
```bash
cp -r /opt/stacks/dex/web /opt/stacks/dex/web.orig
```

| Template | Page |
|---|---|
| `header.html` | Top of every page: `<head>`, stylesheets, favicon, logo bar |
| `footer.html` | Bottom of every page |
| `login.html` | "Log in with …" buttons — shown when there is more than one way to sign in (local password plus e.g. Microsoft) |
| `password.html` | The email and password form |
| `error.html` | Error page (e.g. an unknown redirect address) |
| `logout.html`, `approval.html`, `device*.html`, `oob.html` | Not used by this setup (approval is skipped) |

**What must stay** when you edit — Dex fills these in, and the form breaks without them:
- `{{ template "header.html" . }}` at the top of each page and `{{ template "footer.html" . }}` at the bottom.
- In `password.html`: `action="{{ .PostURL }}"` on the form, and the input names `login`, `password`, and `remember_me`.
- In `login.html`: `{{ range $c := .Connectors }}` … `{{ $c.URL }}` … `{{ end }}` (one button per sign-in method).

**What you can use** inside a template:

| Placeholder | Gives |
|---|---|
| `{{ issuer }}` | The `issuer` name from the `frontend:` block |
| `{{ extra "helpText" }}` | Any value you add under `frontend:` → `extra:` |
| `{{ url .ReqPath "theme/logo.png" }}` | Address of a file in your theme folder (images, fonts) |
| `{{ .UsernamePrompt }}`, `{{ .Invalid }}`, `{{ .Username }}` | In `password.html`: the field label, whether the last try failed, the email typed last time |
| `{{ now \| date "2006" }}` | The current year (plus the other [sprig](https://masterminds.github.io/sprig/) helpers) |

**Example — `password.html`, with your own heading, clearer labels, an error message, and a help line.** Replace the part from `<h2` up to the error box with:
```html
  <h2 class="theme-heading">Sign in to {{ issuer }}</h2>
  <p class="dex-subtle-text">Use your work email and the password you were given.</p>
  <form method="post" action="{{ .PostURL }}">
    <div class="theme-form-row">
      <div class="theme-form-label"><label for="login">Work email</label></div>
      <input tabindex="1" required id="login" name="login" type="email" class="theme-form-input"
             placeholder="name@company.com" {{ if .Username }} value="{{ .Username }}" {{ else }} autofocus {{ end }}/>
    </div>
    <div class="theme-form-row">
      <div class="theme-form-label"><label for="password">Password</label></div>
      <input tabindex="2" required id="password" name="password" type="password" class="theme-form-input"
             {{ if .Invalid }} autofocus {{ end }}/>
    </div>

    {{ if .Invalid }}
      <div id="login-error" class="dex-error-box">That email and password do not match. Try again.</div>
    {{ end }}
```
Leave the rest of the file (remember-me box, Login button, script) as it is. To show the help line from `extra`, add below the form:
```html
  {{ with extra "helpText" }}
    <p class="dex-subtle-text">{{ . }}{{ with extra "helpURL" }} <a href="{{ . }}">Open</a>{{ end }}</p>
  {{ end }}
```

**Example — `footer.html` with a footer line on every page:**
```html
    </div>
    <div class="dex-subtle-text" style="text-align: center; margin: 24px 0;">
      {{ issuer }} · {{ now | date "2006" }}
    </div>
  </body>
</html>
```

Style anything new in `themes/custom/styles.css`; the page already uses the classes `theme-panel`, `theme-heading`, `theme-form-input`, `theme-btn--primary`, `dex-error-box`, and `dex-subtle-text`.

**Apply and check:** Dex reads the templates when it starts, so recreate it after each change:
```bash
cd /opt/stacks/dex && docker compose up -d --force-recreate dex && sleep 3 && docker logs dex --since 1m 2>&1 | grep -iE "template|parse|error"
```
No output means the templates loaded. A line like `parse files: template: password.html:12: …` names the file and line to fix; Dex doesn't start until it's fixed (sign-in is down meanwhile), so fix it, or copy the file back from `web.orig`, and recreate again.

**After updating Dex** (`update-stack.sh dex`): your folder is a copy of the old version's templates. If a new Dex release changes them, the login page can break. Before updating, copy the new files into a fresh folder and carry your changes over — theme files (`themes/custom/`) rarely need changes, templates may. To avoid surprises, pin the Dex image to a version (`ghcr.io/dexidp/dex:v2.x.y`) while you use a custom page.

---

**Related:**
- [Step 6: Dex (sign-in)](../ai-server-setup-guide.md#step-6-dex-sign-in) → Options
