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

// ... (other code above)

subprojects {
    val subprojectRoot = project.projectDir.toPath().root
    val rootProjectRoot = rootProject.projectDir.toPath().root
    if (subprojectRoot == rootProjectRoot) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}

// ---> PASTE THIS NEW BLOCK HERE <---
subprojects {
    pluginManager.withPlugin("com.android.library") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                compileSdk = 37
                defaultConfig {
                    minSdk = 23
                }
            }
        }
    }
}
// ---> END OF NEW BLOCK <---

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}