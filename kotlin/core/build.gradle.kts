import org.jetbrains.kotlin.gradle.dsl.JvmTarget
plugins { kotlin("jvm"); `java-library` }
group = "dev.devicereadout"
version = "0.1.0"
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_1_8) } }
java { sourceCompatibility = JavaVersion.VERSION_1_8; targetCompatibility = JavaVersion.VERSION_1_8 }
dependencies {
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    testImplementation(kotlin("test-junit"))
}
tasks.test { testLogging { events("passed", "failed", "skipped") } }
