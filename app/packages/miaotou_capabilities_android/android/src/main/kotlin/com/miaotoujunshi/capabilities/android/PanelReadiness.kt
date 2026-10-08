package com.miaotoujunshi.capabilities.android

/**
 * How many panel engines one window is allowed to burn before it gives up.
 *
 * **The failure this exists for is silent.** The panel window is created by the
 * plugin and its pixels by a second engine, so an engine that never reaches Dart
 * leaves a window that `dumpsys window` calls `isVisible=true`, that still
 * swallows touches at (12dp, 56dp), and that still tells the platform's freezer
 * the application "has floating or onScreen window, skip to freeze" — while the
 * user sees nothing and reports 「悬浮球不见了」.
 *
 * The host cannot tell a dead engine from a slow one, so it waits [timeoutMs]
 * and then starts another; the first start plus one retry is the whole budget,
 * because a third engine buys nothing the second did not. Past the budget the
 * window is taken down instead, which turns a silent failure into a missing ball
 * the user can act on by relaunching.
 *
 * **Pure on purpose.** The countdown itself lives in the host's `Handler` and
 * needs a Looper, a `WindowManager` and a real engine to exercise; this class is
 * the part of the policy that a JUnit test on a machine with no device attached
 * can still pin, in the spirit of [com.jev.probe.core.ConversationRef]'s tests.
 */
internal class PanelReadiness(
    private val attemptsAllowed: Int = 2,
    val timeoutMs: Long = 10_000L,
) {
    private var attempts = 0

    /** True while another engine start is worth trying. */
    val canStartAgain: Boolean get() = attempts < attemptsAllowed

    /** Counts one engine start. Never refuses one; [canStartAgain] is the gate. */
    fun start() {
        attempts += 1
    }

    /**
     * A panel that answered is not a panel to keep failing.
     *
     * Without this the budget would be spent once per process and a single bad
     * launch would stop the window from ever healing itself again, even after
     * the application had been running happily for an hour.
     */
    fun ready() {
        attempts = 0
    }
}
