package com.jev.probe.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatCaptureServiceTest {
    @Test fun accessibilityEventsCannotReplacePendingReview() {
        assertTrue(shouldIgnoreAccessibilityEvents(reviewPending = true))
    }

    @Test fun accessibilityEventsResumeAfterReview() {
        assertFalse(shouldIgnoreAccessibilityEvents(reviewPending = false))
    }

    @Test fun confirmationWaitsForOverlayFocusToReturnToChat() {
        assertEquals(ReviewConfirmationState.WAIT_FOR_CHAT_WINDOW,
            reviewConfirmationState("com.miaotoujunshi.chat",
                "com.miaotoujunshi.chat", "cn.soulapp.android"))
        assertEquals(ReviewConfirmationState.WAIT_FOR_CHAT_WINDOW,
            reviewConfirmationState(null,
                "com.miaotoujunshi.chat", "cn.soulapp.android"))
    }

    @Test fun confirmationAcceptsOnlyTheOriginalChatApp() {
        assertEquals(ReviewConfirmationState.CHAT_CURRENT,
            reviewConfirmationState("cn.soulapp.android",
                "com.miaotoujunshi.chat", "cn.soulapp.android"))
        assertEquals(ReviewConfirmationState.CHAT_CHANGED,
            reviewConfirmationState("com.tencent.mobileqq",
                "com.miaotoujunshi.chat", "cn.soulapp.android"))
    }
}
