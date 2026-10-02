package com.jev.probe

import android.app.Application
import com.jev.probe.core.SharedMaterial

/**
 * Loads the material all three ports share. It ships inside `assets/` and is
 * read by [SharedMaterial] under its repository path (docs/adr/0006).
 */
class MiaotouApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SharedMaterial.install(this)
    }
}
