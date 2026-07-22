<#--
  Bankerise SEA mobile login theme — username + password step (spec §18.2).
  Overrides base/login/login.ftl. Form field names (username, password) and
  the form action (${url.loginAction}) are unchanged from base so the POST
  to login-actions/authenticate keeps working exactly as Keycloak expects.

  Layout is "passkey-first": a primary CTA slot sits above the
  username/password form so a real passkey/biometric flow can slot in later
  as the top action. Passkeys are DEFERRED for this build (see spec) — the
  CTA below is a visibly disabled placeholder, not a working button.
-->
<#import "template.ftl" as layout>
<#import "passkeys.ftl" as passkeys>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=realm.password && realm.registrationAllowed && !registrationDisabled??; section>
    <#if section = "header">
        ${msg("loginAccountTitle")}
    <#elseif section = "form">

        <p class="sea-subtitle">${msg("seaLoginSubtitle")}</p>

        <#-- Passkey-first primary CTA (spec §10). Passkeys ship in v1: this is
             the top sign-in action, above the username/password form.

             It jumps straight to Keycloak's WebAuthn Passwordless authenticator
             by POSTing that execution's authExecId as `authenticationExecution`
             — the exact mechanism the "Try Another Way" selector uses, surfaced
             here as a one-tap primary action so users get the passkey ceremony
             immediately instead of digging through the selector. The
             authenticator runs usernameless (resident-key / discoverable
             credential), so no username is required first.

             We deliberately do NOT use conditional-UI autofill: that path is
             driven by `enableWebAuthnConditionalUI`, which on this Keycloak is
             set only by the deprecated WebAuthnConditionalUIAuthenticator
             (feature off) — and autofill is unreliable inside WKWebView anyway.

             Rendered only when the passwordless passkey authenticator is
             actually offered as a selection (auth.authenticationSelections), so
             a realm without passkeys — or a step where it is not applicable —
             degrades cleanly to the password form with no dead button. -->
        <#assign seaPasskeyExecId = "">
        <#if auth?? && auth.authenticationSelections??>
            <#list auth.authenticationSelections as sel>
                <#if sel.displayName == "webauthn-passwordless-display-name">
                    <#assign seaPasskeyExecId = sel.authExecId>
                </#if>
            </#list>
        </#if>
        <#if seaPasskeyExecId?has_content>
            <form id="sea-passkey-form" action="${url.loginAction}" method="post">
                <button type="submit" name="authenticationExecution" value="${seaPasskeyExecId}" class="sea-passkey-cta">
                    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">
                        <path d="M12 2a5 5 0 0 0-5 5v3a1 1 0 0 0 2 0V7a3 3 0 1 1 6 0v3a1 1 0 0 0 2 0V7a5 5 0 0 0-5-5Z" fill="currentColor"/>
                        <path d="M6 10h12a1 1 0 0 1 1 1v9a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-9a1 1 0 0 1 1-1Zm6 4a1.5 1.5 0 0 0-1 2.62V18a1 1 0 0 0 2 0v-1.38A1.5 1.5 0 0 0 12 14Z" fill="currentColor"/>
                    </svg>
                    <span>${msg("webauthn-doAuthenticate")}</span>
                </button>
            </form>
            <div class="sea-divider">${msg("seaOrDivider")}</div>
        </#if>

        <div id="kc-form">
          <div id="kc-form-wrapper">
            <#if realm.password>
                <form id="kc-form-login" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post">
                    <#if !usernameHidden??>
                        <div class="sea-form-group">
                            <label for="username" class="sea-label"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>

                            <div class="sea-input-wrap">
                                <input tabindex="2" id="username" class="sea-input" name="username" value="${(login.username!'')}" type="text"
                                       placeholder="<#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("seaUsernameOrEmailPlaceholder")}<#else>${msg("email")}</#if>"
                                       autofocus
                                       autocomplete="${(enableWebAuthnConditionalUI?has_content)?then('username webauthn', 'username')}"
                                       inputmode="<#if realm.loginWithEmailAllowed && realm.registrationEmailAsUsername>email<#else>text</#if>"
                                       autocapitalize="off" autocorrect="off" spellcheck="false"
                                       enterkeyhint="next"
                                       aria-invalid="<#if messagesPerField.existsError('username','password')>true<#else>false</#if>"
                                       <#if messagesPerField.existsError('username','password')>aria-describedby="input-error"</#if>
                                />
                            </div>

                            <#if messagesPerField.existsError('username','password')>
                                <span id="input-error" class="sea-error-text" role="alert" aria-live="assertive">
                                        ${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}
                                </span>
                            </#if>
                        </div>
                    </#if>

                    <div class="sea-form-group">
                        <label for="password" class="sea-label">${msg("password")}</label>

                        <div class="sea-input-wrap has-toggle">
                            <input tabindex="3" id="password" class="sea-input" name="password" type="password"
                                   placeholder="${msg("seaPasswordPlaceholder")}"
                                   autocomplete="current-password"
                                   enterkeyhint="go"
                                   aria-invalid="<#if messagesPerField.existsError('username','password')>true<#else>false</#if>"
                                   <#if messagesPerField.existsError('username','password') && usernameHidden??>aria-describedby="input-error"</#if>
                            />
                            <button class="sea-password-toggle" type="button" id="sea-password-toggle"
                                    aria-label="${msg('showPassword')}" aria-pressed="false" aria-controls="password" tabindex="4">
                                <svg data-icon="show" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">
                                    <path d="M12 5c-5.05 0-9.29 3.11-11 7.5 1.71 4.39 5.95 7.5 11 7.5s9.29-3.11 11-7.5C21.29 8.11 17.05 5 12 5Zm0 12.5a5 5 0 1 1 0-10 5 5 0 0 1 0 10Zm0-8a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z" fill="currentColor"/>
                                </svg>
                                <svg data-icon="hide" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false" style="display:none;">
                                    <path d="M3.28 2.22 2.22 3.28l3.1 3.1C3.32 7.86 1.79 9.72 1 12c1.71 4.39 5.95 7.5 11 7.5 1.8 0 3.5-.4 5.02-1.12l3.7 3.7 1.06-1.06L3.28 2.22ZM12 17.5a5 5 0 0 1-4.8-6.42l1.53 1.53a3 3 0 0 0 3.76 3.76l1.53 1.53a4.98 4.98 0 0 1-2.02.6Zm.18-9.99 5.63 5.63a5 5 0 0 0-5.63-5.63ZM23 12c-.6-1.54-1.5-2.92-2.63-4.05l-1.42 1.42A10.6 10.6 0 0 1 20.82 12a10.9 10.9 0 0 1-2.4 3.53l1.42 1.42C21.03 15.7 22.2 13.98 23 12Z" fill="currentColor"/>
                                </svg>
                            </button>
                        </div>

                        <#if usernameHidden?? && messagesPerField.existsError('username','password')>
                            <span id="input-error" class="sea-error-text" role="alert" aria-live="assertive">
                                    ${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}
                            </span>
                        </#if>
                    </div>

                    <div class="sea-form-options">
                        <#if realm.rememberMe && !usernameHidden??>
                            <label class="sea-checkbox-label">
                                <#if login.rememberMe??>
                                    <input tabindex="5" id="rememberMe" name="rememberMe" type="checkbox" checked>
                                <#else>
                                    <input tabindex="5" id="rememberMe" name="rememberMe" type="checkbox">
                                </#if>
                                ${msg("rememberMe")}
                            </label>
                        </#if>
                        <#if realm.resetPasswordAllowed>
                            <a tabindex="6" class="sea-link" href="${url.loginResetCredentialsUrl}">${msg("doForgotPassword")}</a>
                        </#if>
                    </div>

                    <div id="kc-form-buttons" class="sea-form-group">
                        <input type="hidden" id="id-hidden-input" name="credentialId" <#if auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if>/>
                        <input tabindex="7" class="sea-button sea-button-primary" name="login" id="kc-login" type="submit" value="${msg("doLogIn")}"/>
                    </div>
                </form>
            </#if>
          </div>
        </div>
        <@passkeys.conditionalUIData />

        <#-- Self-contained presentation script: toggles password visibility
             and keeps aria-pressed in sync. No native bridge, no
             postMessage — purely local DOM state. -->
        <script>
            (function () {
                try {
                    var btn = document.getElementById('sea-password-toggle');
                    var input = document.getElementById('password');
                    if (!btn || !input) return;
                    var showIcon = btn.querySelector('[data-icon="show"]');
                    var hideIcon = btn.querySelector('[data-icon="hide"]');
                    var showLabel = "${msg('showPassword')?js_string}";
                    var hideLabel = "${msg('hidePassword')?js_string}";
                    btn.addEventListener('click', function () {
                        var isHidden = input.type === 'password';
                        input.type = isHidden ? 'text' : 'password';
                        btn.setAttribute('aria-pressed', isHidden ? 'true' : 'false');
                        btn.setAttribute('aria-label', isHidden ? hideLabel : showLabel);
                        if (showIcon) { showIcon.style.display = isHidden ? 'none' : ''; }
                        if (hideIcon) { hideIcon.style.display = isHidden ? '' : 'none'; }
                    });
                } catch (e) { /* no-op */ }
            })();
        </script>
    <#elseif section = "info" >
        <#if realm.password && realm.registrationAllowed && !registrationDisabled??>
            <div id="kc-registration-container">
                <div id="kc-registration">
                    <span>${msg("noAccount")} <a tabindex="8" class="sea-link"
                                                 href="${url.registrationUrl}">${msg("doRegister")}</a></span>
                </div>
            </div>
        </#if>
    <#elseif section = "socialProviders" >
        <#if realm.password && social?? && social.providers?has_content>
            <div id="kc-social-providers" class="${properties.kcFormSocialAccountSectionClass!}">
                <hr/>
                <h2>${msg("identity-provider-login-label")}</h2>

                <ul class="${properties.kcFormSocialAccountListClass!} <#if social.providers?size gt 3>${properties.kcFormSocialAccountListGridClass!}</#if>">
                    <#list social.providers as p>
                        <li>
                            <a data-once-link data-disabled-class="${properties.kcFormSocialAccountListButtonDisabledClass!}" id="social-${p.alias}"
                                    class="${properties.kcFormSocialAccountListButtonClass!} <#if social.providers?size gt 3>${properties.kcFormSocialAccountGridItem!}</#if>"
                                    type="button" href="${p.loginUrl}">
                                <#if p.iconClasses?has_content>
                                    <i class="${properties.kcCommonLogoIdP!} ${p.iconClasses!}" aria-hidden="true"></i>
                                    <span class="${properties.kcFormSocialAccountNameClass!} kc-social-icon-text">${p.displayName!}</span>
                                <#else>
                                    <span class="${properties.kcFormSocialAccountNameClass!}">${p.displayName!}</span>
                                </#if>
                            </a>
                        </li>
                    </#list>
                </ul>
            </div>
        </#if>
    </#if>

</@layout.registrationLayout>
