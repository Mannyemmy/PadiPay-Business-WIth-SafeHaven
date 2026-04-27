allprojects {
    repositories {
        google()
        mavenCentral()
        // JitPack: required to resolve com.github.* artifacts (e.g., fingerprint-android)
        maven { url = uri("https://jitpack.io") }
        // QoreID Maven repository
        maven { url = uri("https://repo.qoreid.com/repository/maven-releases/") }
        // Sudo Africa / Tappa SDK Maven repository
        maven {
            url = uri("https://sdk.sudo.africa/repository/maven-releases/")
            credentials {
                username = project.findProperty("maven.repo.username") as String? ?: "allgood"
                password = project.findProperty("maven.repo.password") as String? ?: "H3\$yQ7@N5t"
            }
        }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
