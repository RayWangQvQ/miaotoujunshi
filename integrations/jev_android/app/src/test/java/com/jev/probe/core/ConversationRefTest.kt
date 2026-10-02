package com.jev.probe.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversationRefTest {

    @Test fun labelNamesAppAndThread() {
        assertEquals("QQ · 张三", ConversationRef("com.tencent.mobileqq", "张三").displayLabel())
    }

    @Test fun labelSaysSoWhenTheThreadIsUnknown() {
        assertEquals("QQ · 未识别会话", ConversationRef("com.tencent.mobileqq", null).displayLabel())
        assertEquals("QQ · 未识别会话", ConversationRef("com.tencent.mobileqq", "   ").displayLabel())
    }

    @Test fun labelKeepsAThreadWeKnowEvenWhenTheAppIsUnknown() {
        assertEquals("张三", ConversationRef("com.example.unknown", "张三").displayLabel())
    }

    @Test fun labelNeverEchoesARawPackageName() {
        // The overlay header must not show "com.example.unknown" to the user.
        assertEquals("未识别会话", ConversationRef("com.example.unknown", null).displayLabel())
        assertEquals(ConversationRef.UNKNOWN_LABEL, ConversationRef.NONE.displayLabel())
    }

    @Test fun identityNeedsBothAppAndThread() {
        assertTrue(ConversationRef("com.tencent.mobileqq", "张三").isIdentified)
        assertFalse(ConversationRef("com.tencent.mobileqq", null).isIdentified)
        assertFalse(ConversationRef("", "张三").isIdentified)
    }

    @Test fun anotherThreadOfTheSameAppIsAnotherConversation() {
        // This is the comparison the read-only guard rests on: moving to a
        // different thread of the same app must not look like "same chat".
        assertNotEquals(
            ConversationRef("com.tencent.mobileqq", "张三"),
            ConversationRef("com.tencent.mobileqq", "李四"))
    }

    @Test fun aThreadWeKnowBeatsAnAppWeDoNot() {
        // Same app, title dropped: the guard must treat that as a different
        // conversation rather than assume the title is unchanged.
        assertNotEquals(
            ConversationRef("com.tencent.mobileqq", "张三"),
            ConversationRef("com.tencent.mobileqq", null))
    }

    @Test fun displayNamesAreSharedWithTheKnowledgeList() {
        assertEquals("微信", ChatApps.displayName("com.tencent.mm"))
        assertEquals("QQ", ChatApps.displayName("com.tencent.mobileqq"))
        assertEquals("飞书", ChatApps.displayName("com.ss.android.lark"))
        assertEquals("X", ChatApps.displayName("com.twitter.android"))
        // Null, not the package: the caller decides what to fall back to.
        assertNull(ChatApps.displayName("com.example.unknown"))
        assertNull(ChatApps.displayName(null))
    }
}
