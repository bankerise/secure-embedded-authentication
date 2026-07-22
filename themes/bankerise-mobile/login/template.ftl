<#--
  Bankerise SEA mobile login theme — layout (spec §18.2).

  Overrides base/login/template.ftl. This is the ENTIRE visual surface shown
  inside a chromeless, hardened iOS WKWebView, so it strips all Keycloak
  chrome (header banner, "powered by" footer, language <select>) and renders
  a single-column native-app-style screen: brand mark, title, form, messages,
  footer link area.

  The FreeMarker macro contract (registrationLayout, nested sections
  "header" / "show-username" / "form" / "socialProviders" / "info") is
  preserved exactly so every base page (login.ftl, login-password.ftl,
  login-otp.ftl, etc.) keeps working unmodified against this layout.
-->
<#import "footer.ftl" as loginFooter>
<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}" lang="${lang}"<#if realm.internationalizationEnabled> dir="${(locale.rtl)?then('rtl','ltr')}"</#if>>

<head>
    <#-- Defensive, self-contained explicit dark/light override (spec §18.2 pt.4).
         Runs before the stylesheet is applied so there is no flash of the wrong
         theme. `prefers-color-scheme` (in mobile.css) remains the primary signal
         driven by the device/app appearance; this only overrides it when the
         host app explicitly passes theme_dark=true|false or theme=dark|light on
         the authorize URL. No native bridge, no postMessage — just our own
         inline script reading its own location. -->
    <script>
        (function () {
            try {
                var params = new URLSearchParams(window.location.search);
                var themeDark = params.get('theme_dark');
                var theme = params.get('theme');
                var root = document.documentElement;
                if (themeDark === 'true') {
                    root.setAttribute('data-theme', 'dark');
                } else if (themeDark === 'false') {
                    root.setAttribute('data-theme', 'light');
                } else if (theme === 'dark') {
                    root.setAttribute('data-theme', 'dark');
                } else if (theme === 'light') {
                    root.setAttribute('data-theme', 'light');
                }
            } catch (e) {
                /* no-op: fall back to prefers-color-scheme */
            }
        })();
    </script>

    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="color-scheme" content="light dark">
    <meta name="robots" content="noindex, nofollow">

    <#if properties.meta?has_content>
        <#list properties.meta?split(' ') as meta>
            <meta name="${meta?split('==')[0]}" content="${meta?split('==')[1]}"/>
        </#list>
    </#if>
    <title>${msg("loginTitle",(realm.displayName!''))}</title>
    <#if properties.stylesCommon?has_content>
        <#list properties.stylesCommon?split(' ') as style>
            <link href="${url.resourcesCommonPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.scripts?has_content>
        <#list properties.scripts?split(' ') as script>
            <script src="${url.resourcesPath}/${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <#if scripts??>
        <#list scripts as script>
            <script src="${script}" type="text/javascript"></script>
        </#list>
    </#if>

    <#-- Import map for the ES-module resources shipped by the base/common
         themes — currently `rfc4648`, bare-imported at the top of
         webauthnRegister.js and webauthnAuthenticate.js. Because this theme
         fully replaces base/login/template.ftl, it MUST re-emit this map (base
         emits its own): without it the browser cannot resolve the bare
         `import { base64url } from "rfc4648"`, the WebAuthn module fails to
         load, and the passkey register/authenticate button silently never
         wires up its click handler. Kept in sync with base/login/template.ftl. -->
    <script type="importmap">
        {
            "imports": {
                "rfc4648": "${url.resourcesCommonPath}/vendor/rfc4648/rfc4648.js"
            }
        }
    </script>
</head>

<body class="${properties.kcBodyClass!}" data-page-id="login-${pageId}">
<div class="sea-screen">
    <div class="sea-card">

        <#-- App brand mark — replaces the Keycloak kc-header banner entirely. -->
        <div class="sea-brand">
            <span class="sea-brand__logo" aria-hidden="true">
                <svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg" role="img" aria-hidden="true" focusable="false">
                    <rect x="1" y="1" width="46" height="46" rx="13" fill="var(--sea-color-primary)"/>
                    <path d="M14 32V19.5C14 18.6716 14.6716 18 15.5 18H17.5C18.3284 18 19 18.6716 19 19.5V32"
                          stroke="var(--sea-color-text-on-primary)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
                    <path d="M22 32V14.5C22 13.6716 22.6716 13 23.5 13H25.5C26.3284 13 27 13.6716 27 14.5V32"
                          stroke="var(--sea-color-text-on-primary)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
                    <path d="M30 32V24.5C30 23.6716 30.6716 23 31.5 23H33.5C34.3284 23 35 23.6716 35 24.5V32"
                          stroke="var(--sea-color-text-on-primary)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
                    <path d="M12 32H36" stroke="var(--sea-color-text-on-primary)" stroke-width="2.4" stroke-linecap="round"/>
                </svg>
            </span>
            <span class="sea-brand__wordmark">Bankerise</span>
        </div>

        <#-- Attempted-username / restart-flow affordance for multi-step auth
             (e.g. after login-username.ftl, before login-password.ftl). Kept
             functional, restyled minimally. -->
        <#if auth?has_content && auth.showUsername() && !auth.showResetCredentials()>
            <div id="kc-username" class="sea-form-group">
                <div class="sea-checkbox-label" style="justify-content: space-between;">
                    <label id="kc-attempted-username">${auth.attemptedUsername}</label>
                    <a id="reset-login" class="sea-link" href="${url.loginRestartFlowUrl}" aria-label="${msg("restartLoginTooltip")}">${msg("restartLoginTooltip")}</a>
                </div>
            </div>
        </#if>

        <h1 id="kc-page-title" class="sea-title"><#nested "header"></h1>

        <#if displayRequiredFields>
            <p class="sea-subtitle"><span aria-hidden="true">*</span> ${msg("requiredFields")}</p>
        </#if>

        <#-- Messages / errors. role="alert" + aria-live ensures screen readers
             announce validation errors as soon as they render (spec §19). -->
        <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
            <div class="sea-alert pf-m-<#if message.type = 'error'>danger<#else>${message.type}</#if>"
                 role="alert" aria-live="assertive">
                <span class="sea-alert__icon" aria-hidden="true">
                    <#if message.type = 'success'><span class="${properties.kcFeedbackSuccessIcon!}"></span></#if>
                    <#if message.type = 'warning'><span class="${properties.kcFeedbackWarningIcon!}"></span></#if>
                    <#if message.type = 'error'><span class="${properties.kcFeedbackErrorIcon!}"></span></#if>
                    <#if message.type = 'info'><span class="${properties.kcFeedbackInfoIcon!}"></span></#if>
                </span>
                <span>${kcSanitize(message.summary)?no_esc}</span>
            </div>
        </#if>

        <#nested "form">

        <#if auth?has_content && auth.showTryAnotherWayLink()>
            <form id="kc-select-try-another-way-form" action="${url.loginAction}" method="post">
                <div class="sea-form-group">
                    <input type="hidden" name="tryAnotherWay" value="on"/>
                    <a href="#" class="sea-link" id="try-another-way"
                       onclick="document.forms['kc-select-try-another-way-form'].requestSubmit();return false;">${msg("doTryAnotherWay")}</a>
                </div>
            </form>
        </#if>

        <#nested "socialProviders">

        <#if displayInfo>
            <div id="kc-info" class="sea-footer">
                <#nested "info">
            </div>
        </#if>

    </div>
</div>
</body>
</html>
</#macro>
