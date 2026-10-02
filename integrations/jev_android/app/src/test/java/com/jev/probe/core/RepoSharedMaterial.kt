package com.jev.probe.core

import java.io.File

/**
 * JVM unit tests have no AssetManager, so they bind [SharedMaterial] to the very
 * same repository files the APK ships. Nothing is copied: the test keeps reading
 * the single source instead of a second one written for the test's sake.
 */
fun installRepoSharedMaterial() {
    var dir: File? = File("").absoluteFile
    while (dir != null && !File(dir, "goutoujunshi/SKILL.md").isFile) dir = dir.parentFile
    val root = requireNotNull(dir) { "找不到仓库根目录（缺少 goutoujunshi/SKILL.md）" }
    SharedMaterial.install { path -> File(root, path).readText() }
}
