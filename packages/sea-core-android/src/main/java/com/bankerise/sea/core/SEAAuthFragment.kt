package com.bankerise.sea.core

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout

/**
 * Fragment variant of the auth surface (§4.1 — "SEAActivity or Fragment
 * in RN host Activity").
 *
 * Shares all WebView / navigation / terminal-callback logic with
 * [SEAAuthActivity] via [SEAAuthDelegate]. This Fragment is the primary
 * integration point for React Native host Activities (§4.2) and for
 * fully-native apps that prefer Fragment-based navigation.
 *
 * Arguments: pass a [Bundle] with the same extras defined in
 * [SEAAuthActivity.Companion].
 */
class SEAAuthFragment : androidx.fragment.app.Fragment() {

    private var delegate: SEAAuthDelegate? = null

    companion object {
        fun newInstance(config: SEAConfig): SEAAuthFragment {
            return SEAAuthFragment().apply {
                arguments = Bundle().apply {
                    putString(SEAAuthActivity.EXTRA_AUTHORIZED_URL, config.authorizeUrl.toString())
                    putString(SEAAuthActivity.EXTRA_CALLBACK_SCHEME, config.callbackScheme)
                    putStringArrayList(SEAAuthActivity.EXTRA_ALLOWED_DOMAINS, ArrayList(config.allowedDomains))
                    putString(SEAAuthActivity.EXTRA_PRESENTATION, config.presentation.name)
                    putLong(SEAAuthActivity.EXTRA_TIMEOUT_MS, config.timeoutMs)
                    putString(SEAAuthActivity.EXTRA_CAPTURE_POLICY, config.capturePolicy.name)
                }
            }
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val args = requireArguments()
        val config = SEAAuthActivity.configFrom(
            android.net.Uri.parse(args.getString(SEAAuthActivity.EXTRA_AUTHORIZED_URL, "")),
            args.getString(SEAAuthActivity.EXTRA_CALLBACK_SCHEME, ""),
            args.getStringArrayList(SEAAuthActivity.EXTRA_ALLOWED_DOMAINS) ?: emptyList(),
            args.getString(SEAAuthActivity.EXTRA_PRESENTATION, "SHEET"),
            args.getLong(SEAAuthActivity.EXTRA_TIMEOUT_MS, 120_000L),
            args.getString(SEAAuthActivity.EXTRA_CAPTURE_POLICY, "WARN")
        )
        val env = SEAEnvironment(
            authDomains = config.allowedDomains.mapTo(HashSet()) { SEAEnvironment.normalizeHost(it) },
            callbackScheme = config.callbackScheme
        )
        val userCallbacks = SEASession.takePendingCallbacks()

        val wrappedCallbacks = SEASession.Callbacks(
            onCaptured = { userCallbacks?.onCaptured?.invoke(it) },
            onCancelled = {
                userCallbacks?.onCancelled?.invoke()
                dismissSelf()
            },
            onError = { error ->
                userCallbacks?.onError?.invoke(error)
                dismissSelf()
            }
        )

        val delegate = SEAAuthDelegate(config, env, wrappedCallbacks)
        this.delegate = delegate

        val root = FrameLayout(requireContext())

        if (config.presentation == SEAPresentation.SHEET) {
            val sheetView = delegate.createSheetView(root) { dismissSelf() }
            root.addView(sheetView, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ))
        } else {
            val webViewContainer = delegate.createView(root)
            root.addView(webViewContainer, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ))
        }

        return root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        delegate?.onViewCreated()
    }

    override fun onResume() {
        super.onResume()
        delegate?.onResume()
    }

    override fun onPause() {
        super.onPause()
        delegate?.onPause()
    }

    override fun onDestroyView() {
        delegate?.onDestroy()
        delegate = null
        super.onDestroyView()
    }

    private fun dismissSelf() {
        parentFragmentManager.beginTransaction()
            .remove(this)
            .commitAllowingStateLoss()
    }

    /**
     * Handle back press. Returns `true` if consumed (WebView went back),
     * `false` if the Fragment should be dismissed.
     */
    fun handleBackPress(): Boolean {
        return delegate?.handleBackPress() ?: false
    }
}
