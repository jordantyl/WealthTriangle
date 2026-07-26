buildscript {
    val kotlin_version = "1.7.10"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        // Kotlin uses brackets () and double quotes ""
        classpath("com.android.tools.build:gradle:7.3.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Correct way to set build directory in Kotlin DSL
rootProject.buildDir = File("../build")
subprojects {
    project.buildDir = File("${rootProject.buildDir}/${project.name}")
}
// Some older Flutter plugins (e.g. google_mlkit_commons 0.6.1) hardcode
// their own compileSdkVersion far below the app's (29 vs. this app's 36),
// which breaks release-build resource linking the moment a dependency
// references a resource newer than API 29 (found via "resource
// android:attr/lStar not found" — lStar was added in API 31). Rather than
// upgrade a plugin that might carry unrelated breaking changes, force every
// Android subproject to compile against the same SDK as the app. This must
// be registered before evaluationDependsOn() below forces early evaluation
// of some subprojects, or afterEvaluate() throws "already evaluated".
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {
            it.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}