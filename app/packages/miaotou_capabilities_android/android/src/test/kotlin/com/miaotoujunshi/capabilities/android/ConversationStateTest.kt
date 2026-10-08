package com.miaotoujunshi.capabilities.android

import com.jev.probe.core.ChatApps
import com.jev.probe.core.ConversationRef
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversationStateTest {
    @Test
    fun missingIdentityPartsRemainLegalAndDistinct() {
        val complete = ConversationRef("com.tencent.mobileqq", "张三")
        val missingTitle = ConversationRef("com.tencent.mobileqq", null)
        val missingPackage = ConversationRef("", "张三")

        assertFalse(missingTitle.isIdentified)
        assertFalse(missingPackage.isIdentified)
        assertNotEquals(complete, missingTitle)
        assertNotEquals(complete, missingPackage)
    }

    @Test
    fun theNameTheWireCarriesFallsBackToThePackage() {
        // No Context means PackageManager is unavailable, so the package name is
        // all that names the app (ADR-0026), and null is reserved for a
        // conversation with no package at all. The order that turns that null
        // into 「未知应用」 is the domain's (ADR-0028): it is not implemented
        // twice.
        assertEquals("com.example.private", ChatApps.displayName("com.example.private", null))
        assertEquals("微信", ChatApps.displayName("com.tencent.mm", null))
        assertNull(ChatApps.displayName("", null))
        assertNull(ChatApps.displayName(null, null))
    }

    @Test
    fun captureServiceOwnsReadOnlyComparison() {
        val bound = ConversationRef("com.tencent.mobileqq", "张三")
        val same = ConversationRef("com.tencent.mobileqq", "张三")
        val changed = ConversationRef("com.tencent.mobileqq", "李四")

        assertFalse(bound != same)
        assertTrue(bound != changed)
    }
}
