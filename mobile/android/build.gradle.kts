allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Compile every Android plugin against API 36.
//
// file_picker (added for the optional petition document) pulls in
// flutter_plugin_android_lifecycle, which now requires its dependents to
// compile against 36; the plugins themselves still default to 34 and the
// build fails on the mismatch. Raising it here rather than pinning an older
// plugin keeps the dependency graph current.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val setter = ext.javaClass.methods.firstOrNull {
                it.name == "setCompileSdkVersion" && it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Integer.TYPE
            }
            setter?.invoke(ext, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
