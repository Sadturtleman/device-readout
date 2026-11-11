import org.jetbrains.kotlin.gradle.dsl.JvmTarget
plugins { id("com.android.library"); kotlin("android") }
group = "dev.devicereadout"
version = "0.1.0"
android {
    namespace = "dev.devicereadout.android"
    compileSdk = 35
    buildToolsVersion = "35.0.0"
    defaultConfig {
        minSdk = 26
        targetSdk = providers.gradleProperty("deviceReadoutTestTargetSdk").orElse("35").get().toInt()
        testInstrumentationRunner = "dev.devicereadout.android.ContractInstrumentation"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            it.systemProperty("robolectric.dependency.repo.url", "https://repo.maven.apache.org/maven2")
            // Scope the resolver's download lock and Maven cache to this test JVM's workspace.
            it.systemProperty("user.home", rootProject.file("../.tools/robolectric").also {directory -> directory.mkdirs()}.absolutePath)
            it.systemProperty("maven.repo.local", rootProject.file("../.tools/robolectric/repository").absolutePath)
            it.systemProperty("java.io.tmpdir", rootProject.file("../.tools/rt").also {directory -> directory.mkdirs()}.absolutePath)
            it.jvmArgs("--add-opens=java.base/java.lang=ALL-UNNAMED", "--add-opens=java.base/java.util=ALL-UNNAMED", "--add-opens=java.base/java.io=ALL-UNNAMED")
            it.testLogging { events("passed", "failed", "skipped") }
        }
    }
}
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_1_8) } }
dependencies {
    api(project(":core"))
    testImplementation(kotlin("test-junit"))
    testImplementation("org.robolectric:robolectric:4.16")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
