<#--
  Bankerise SEA mobile login theme — WebAuthn passwordless authenticate step.
  Overrides base/login/webauthn-authenticate.ftl.

  The ONLY change from stock is the trailing <script> block: stock binds the
  ceremony to an explicit tap on #authenticateWebAuthnButton, which forces a
  SECOND tap after the page-1 passkey CTA already navigated here. We add a
  best-effort AUTO-trigger on page load so the native passkey sheet appears
  immediately, while keeping the button as a fallback.

  Everything else (hidden form fields, authenticator list, POST target) is
  copied verbatim from base so the round-trip to login-actions keeps working
  exactly as Keycloak expects.
-->
<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=(realm.registrationAllowed && !registrationDisabled??); section>
    <#if section = "title">
     title
    <#elseif section = "header">
        ${msg("webauthn-login-title")}
    <#elseif section = "form">
        <div id="kc-form-webauthn" class="${properties.kcFormClass!}">
            <form id="webauth" action="${url.loginAction}" method="post">
                <input type="hidden" id="clientDataJSON" name="clientDataJSON"/>
                <input type="hidden" id="authenticatorData" name="authenticatorData"/>
                <input type="hidden" id="signature" name="signature"/>
                <input type="hidden" id="credentialId" name="credentialId"/>
                <input type="hidden" id="userHandle" name="userHandle"/>
                <input type="hidden" id="error" name="error"/>
            </form>

            <div class="${properties.kcFormGroupClass!} no-bottom-margin">
                <#if authenticators??>
                    <form id="authn_select" class="${properties.kcFormClass!}">
                        <#list authenticators.authenticators as authenticator>
                            <input type="hidden" name="authn_use_chk" value="${authenticator.credentialId}"/>
                        </#list>
                    </form>

                    <#if shouldDisplayAuthenticators?? && shouldDisplayAuthenticators>
                        <#if authenticators.authenticators?size gt 1>
                            <p class="${properties.kcSelectAuthListItemTitle!}">${msg("webauthn-available-authenticators")}</p>
                        </#if>

                        <div class="${properties.kcFormClass!}">
                            <#list authenticators.authenticators as authenticator>
                                <div id="kc-webauthn-authenticator-item-${authenticator?index}" class="${properties.kcSelectAuthListItemClass!}">
                                    <div class="${properties.kcSelectAuthListItemIconClass!}">
                                        <i class="${(properties['${authenticator.transports.iconClass}'])!'${properties.kcWebAuthnDefaultIcon!}'} ${properties.kcSelectAuthListItemIconPropertyClass!}"></i>
                                    </div>
                                    <div class="${properties.kcSelectAuthListItemBodyClass!}">
                                        <div id="kc-webauthn-authenticator-label-${authenticator?index}"
                                             class="${properties.kcSelectAuthListItemHeadingClass!}">
                                            ${authenticator.label}
                                        </div>

                                        <#if authenticator.transports?? && authenticator.transports.displayNameProperties?has_content>
                                            <div id="kc-webauthn-authenticator-transport-${authenticator?index}"
                                                 class="${properties.kcSelectAuthListItemDescriptionClass!}">
                                                <#list authenticator.transports.displayNameProperties as nameProperty>
                                                    <span>${msg(nameProperty)}</span>
                                                    <#if nameProperty?has_next>
                                                        <span>, </span>
                                                    </#if>
                                                </#list>
                                            </div>
                                        </#if>

                                        <div class="${properties.kcSelectAuthListItemDescriptionClass!}">
                                            <span id="kc-webauthn-authenticator-createdlabel-${authenticator?index}">
                                                ${msg('webauthn-createdAt-label')}
                                            </span>
                                            <span id="kc-webauthn-authenticator-created-${authenticator?index}">
                                                ${authenticator.createdAt}
                                            </span>
                                        </div>
                                    </div>
                                    <div class="${properties.kcSelectAuthListItemFillClass!}"></div>
                                </div>
                            </#list>
                        </div>
                    </#if>
                </#if>

                <div id="kc-form-buttons" class="${properties.kcFormButtonsClass!}">
                    <input id="authenticateWebAuthnButton" type="button" autofocus="autofocus"
                           value="${msg("webauthn-doAuthenticate")}"
                           class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonBlockClass!} ${properties.kcButtonLargeClass!}"/>
                </div>
            </div>
        </div>

    <script type="module">
        <#outputformat "JavaScript">
        import { authenticateByWebAuthn, returnSuccess } from "${url.resourcesPath}/js/webauthnAuthenticate.js";
        import { base64url } from "rfc4648";

        const input = {
            isUserIdentified : ${isUserIdentified},
            challenge : ${challenge?c},
            userVerification : ${userVerification?c},
            rpId : ${rpId?c},
            createTimeout : ${createTimeout?c},
            errmsg : ${msg("webauthn-unsupported-browser-text")?c}
        };

        // Manual fallback — identical to stock: an explicit tap runs the
        // ceremony and (through the module) posts success OR failure upstream.
        const authButton = document.getElementById('authenticateWebAuthnButton');
        authButton.addEventListener("click", function () {
            authenticateByWebAuthn(input);
        }, { once: true });

        // SEA UX (spec §10): skip the extra tap. Auto-attempt the ceremony as
        // soon as this passwordless page loads so the native passkey sheet
        // shows immediately after the page-1 CTA. A blocked/failed attempt is
        // SWALLOWED here and is NOT posted to Keycloak: WebKit may require a
        // fresh user activation that did not survive the navigation from
        // page 1, in which case we silently leave the button for one manual
        // tap. Worst case == stock behavior; best case == the second tap is
        // gone. Only an explicit button tap ever reports failure upstream.
        (async function autoTry() {
            if (!window.PublicKeyCredential) { return; }
            const publicKey = {
                rpId: input.rpId,
                challenge: base64url.parse(input.challenge, { loose: true })
            };
            if (input.createTimeout !== 0) { publicKey.timeout = input.createTimeout * 1000; }
            if (input.userVerification !== 'not specified') { publicKey.userVerification = input.userVerification; }

            // Mirror the module's allowCredentials handling: usernameless
            // (passkey-first) flows have isUserIdentified=false and use an
            // empty allowList (discoverable credential); an identified step
            // restricts to the offered credential ids.
            if (input.isUserIdentified) {
                const authnUse = document.forms['authn_select'] && document.forms['authn_select'].authn_use_chk;
                const allow = [];
                if (authnUse !== undefined) {
                    const entries = (authnUse.length === undefined) ? [authnUse] : Array.from(authnUse);
                    entries.forEach(function (e) {
                        allow.push({ id: base64url.parse(e.value, { loose: true }), type: 'public-key' });
                    });
                }
                if (allow.length) { publicKey.allowCredentials = allow; }
            }

            try {
                const result = await navigator.credentials.get({ publicKey: publicKey });
                returnSuccess(result);
            } catch (e) {
                // Leave the button for a manual tap. No upstream failure posted.
            }
        })();
        </#outputformat>
    </script>

    <#elseif section = "info">
        <#if realm.registrationAllowed && !registrationDisabled??>
            <div id="kc-registration">
                <span>${msg("noAccount")} <a tabindex="6" href="${url.registrationUrl}">${msg("doRegister")}</a></span>
            </div>
        </#if>
    </#if>
</@layout.registrationLayout>
