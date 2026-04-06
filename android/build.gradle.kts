fun Project.enforceCompileSdk(minCompileSdk: Int) {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        val currentCompileSdk =
            androidExtension.javaClass.methods
                .firstOrNull { it.name == "getCompileSdkVersion" && it.parameterCount == 0 }
                ?.invoke(androidExtension)
                ?.toString()
                ?.removePrefix("android-")
                ?.toIntOrNull()
                ?: 0

        if (currentCompileSdk >= minCompileSdk) {
            return@afterEvaluate
        }

        val candidateSetters =
            androidExtension.javaClass.methods.filter {
                it.parameterCount == 1 &&
                    it.name in setOf("setCompileSdk", "setCompileSdkVersion", "compileSdkVersion")
            }

        val setter =
            candidateSetters.firstOrNull {
                val parameterType = it.parameterTypes.single()
                parameterType == Int::class.javaPrimitiveType ||
                    parameterType == Int::class.javaObjectType ||
                    parameterType == Any::class.java
            } ?: candidateSetters.firstOrNull {
                it.parameterTypes.single() == String::class.java
            } ?: return@afterEvaluate

        val argument =
            when (setter.parameterTypes.single()) {
                Int::class.javaPrimitiveType,
                Int::class.javaObjectType,
                Any::class.java -> minCompileSdk
                String::class.java -> "android-$minCompileSdk"
                else -> return@afterEvaluate
            }

        setter.invoke(androidExtension, argument)
    }
}

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
    enforceCompileSdk(36)
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
