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
// Some plugins (stellar_flutter_sdk) ship compiled against an older Android API than their own AndroidX
// dependencies require (checkReleaseAarMetadata fails). Compile every library plugin against API 36.
// compileSdk does not change targetSdk or minSdk, so runtime behaviour is unchanged.
subprojects {
    val raise = {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.compileSdk = 36
    }
    if (state.executed) raise() else afterEvaluate { raise() }
}
subprojects {
    project.evaluationDependsOn(":app")
}
