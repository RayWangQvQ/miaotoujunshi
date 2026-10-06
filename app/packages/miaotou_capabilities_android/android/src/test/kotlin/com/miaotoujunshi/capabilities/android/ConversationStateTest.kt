package com.miaotoujunshi.capabilities.android

import com.jev.probe.core.ConversationRef
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
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
    fun displayLabelFallsBackToThePackageThenThePlaceholder() {
        // No Context means PackageManager is unavailable, so the package name
        // itself is the app label (ADR-0026). Only NONE drops to the placeholder.
        assertEquals(
            "com.example.private · ${ConversationRef.UNKNOWN_LABEL}",
            ConversationRef("com.example.private", null).displayLabel(null),
        )
        assertEquals(
            ConversationRef.UNKNOWN_LABEL,
            ConversationRef("", null).displayLabel(null),
        )
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
