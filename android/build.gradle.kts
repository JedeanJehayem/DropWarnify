import org.gradle.api.file.Directory
import org.gradle.api.tasks.Delete

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // 🔹 Mesmo AGP do settings.gradle.kts
        classpath("com.android.tools.build:gradle:8.11.1")
        // Kotlin alinhado
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        // 🔹 JitPack pra permitir baixar paho.mqtt.android
        maven { url = uri("https://jitpack.io") }
    }
}

// ❌ Removido o bloco configurations.all { ... } que tentava forçar versões de AndroidX

// ====== Mantendo seu esquema de build dir customizado ======
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
