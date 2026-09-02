import com.android.build.api.artifact.SingleArtifact
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.didww.didww_verification_sms_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.didww.didww_verification_sms_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// ---------------------------------------------------------------------------
// The permission assertion.
// ---------------------------------------------------------------------------

/**
 * Asserts that an app using this plugin declares no SMS or call-log permission, and that the
 * merged manifest's component set is still the one that was reviewed.
 *
 * Two checks rather than either. The three named assertions state the criterion a reader can
 * decide. The golden catches a *future* Play Services or AndroidX bump contributing something
 * nobody typed, which a name allowlist by construction cannot.
 *
 * The golden is a normalised projection — component tag plus `android:name`, sorted — and not
 * the raw manifest, because a golden that churns on `uses-sdk`, `versionCode` or attribute
 * reordering invites reflexive regeneration, which is the same failure by another route.
 */
abstract class CheckManifestComponents : DefaultTask() {

    @get:InputFile
    abstract val mergedManifest: RegularFileProperty

    @get:InputFile
    abstract val golden: RegularFileProperty

    @get:OutputFile
    abstract val report: RegularFileProperty

    @TaskAction
    fun check() {
        val document = DocumentBuilderFactory.newInstance()
            .apply { isNamespaceAware = true }
            .newDocumentBuilder()
            .parse(mergedManifest.get().asFile)

        val found = COMPONENT_TAGS.flatMap { tag ->
            val nodes = document.getElementsByTagName(tag)
            (0 until nodes.length).mapNotNull { index ->
                val name = (nodes.item(index) as Element).getAttributeNS(ANDROID_NS, "name")
                if (name.isEmpty()) null else "$tag $name"
            }
        }.distinct().sorted()

        val reportFile = report.get().asFile
        reportFile.parentFile.mkdirs()
        reportFile.writeText(found.joinToString(separator = "\n", postfix = "\n"))

        val missing = REQUIRED_PERMISSIONS.filterNot { "uses-permission $it" in found }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "The merged manifest is missing ${missing.joinToString()}. Flutter's template " +
                    "declares INTERNET in the debug and profile manifests only, so a release " +
                    "build without it has no network.",
            )
        }

        val forbidden = found.filter { it.substringAfter(' ') in FORBIDDEN_PERMISSIONS }
        if (forbidden.isNotEmpty()) {
            throw GradleException(
                "The merged manifest declares ${forbidden.joinToString()}. The SMS Retriever " +
                    "API needs none of these, and they are the ones that draw Play Console review.",
            )
        }

        val expected = golden.get().asFile.readLines().filter { it.isNotBlank() }
        val added = found - expected.toSet()
        val removed = expected - found.toSet()
        if (added.isEmpty() && removed.isEmpty()) return

        throw GradleException(
            buildString {
                appendLine("The merged manifest's component set changed:")
                added.forEach { appendLine("  + $it") }
                removed.forEach { appendLine("  - $it") }
                appendLine("If every line above is intended, copy")
                appendLine("  $reportFile")
                appendLine("over")
                appendLine("  ${golden.get().asFile}")
            },
        )
    }

    private companion object {
        const val ANDROID_NS = "http://schemas.android.com/apk/res/android"

        val COMPONENT_TAGS = listOf(
            "uses-permission",
            "uses-permission-sdk-23",
            "permission",
            "uses-feature",
            "activity",
            "activity-alias",
            "service",
            "receiver",
            "provider",
            "uses-library",
        )

        val REQUIRED_PERMISSIONS = setOf("android.permission.INTERNET")

        val FORBIDDEN_PERMISSIONS = setOf(
            "android.permission.RECEIVE_SMS",
            "android.permission.READ_SMS",
            "android.permission.READ_CALL_LOG",
        )
    }
}

val checkManifestComponents = tasks.register("checkManifestComponents") {
    group = "verification"
    description = "Checks every variant's merged manifest for SMS permissions and drift."
}

androidComponents {
    onVariants { variant ->
        val capitalised = variant.name.replaceFirstChar { it.uppercase() }
        val task = tasks.register<CheckManifestComponents>("check${capitalised}ManifestComponents") {
            group = "verification"
            description = "Checks the ${variant.name} merged manifest."
            mergedManifest.set(variant.artifacts.get(SingleArtifact.MERGED_MANIFEST))
            golden.set(layout.projectDirectory.file("manifest-golden-${variant.name}.txt"))
            report.set(layout.buildDirectory.file("reports/manifest/${variant.name}-components.txt"))
        }
        checkManifestComponents.configure { dependsOn(task) }
    }
}
