package com.miaotoujunshi.capabilities.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The budget a panel window gets to bring an engine up.
 *
 * Written against the device state this was added for: the window present and
 * `isVisible=true` while the engine's Dart isolate sat parked — the ball was
 * invisible for minutes and nothing noticed. The expectations below are the
 * decision table only; the `Handler` that counts the seconds needs a device and
 * is not covered here.
 */
class PanelReadinessTest {

    @Test
    fun oneStartLeavesRoomForOneRetry() {
        val readiness = PanelReadiness()

        assertTrue(readiness.canStartAgain)
        readiness.start()
        assertTrue(
            "the first engine is allowed to fail once before the window is taken down",
            readiness.canStartAgain,
        )
        readiness.start()
        assertFalse(
            "a third engine buys nothing the second did not",
            readiness.canStartAgain,
        )
    }

    @Test
    fun aPanelThatAnsweredEarnsTheBudgetBack() {
        val readiness = PanelReadiness()
        readiness.start()
        readiness.start()
        assertFalse(readiness.canStartAgain)

        readiness.ready()

        assertTrue(
            "an hour of working panel must not be spent by one bad launch",
            readiness.canStartAgain,
        )
    }

    @Test
    fun startingNeverRefusesByItself() {
        // start() counts; canStartAgain is what the host asks. Keeping them
        // apart is what stops the rebuild branch from looping: it re-shows only
        // while the budget lasts, and show() always gets its engine.
        val readiness = PanelReadiness()
        repeat(5) { readiness.start() }
        assertFalse(readiness.canStartAgain)
        assertEquals(10_000L, readiness.timeoutMs)
    }
}
