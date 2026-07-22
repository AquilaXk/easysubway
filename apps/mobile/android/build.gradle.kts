allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 추적되는 lockfile은 apps/mobile/android/app/gradle.lockfile 하나다.
// Flutter 플러그인 서브프로젝트에 lockAllConfigurations를 걸면 pub-cache 쪽
// 미커밋 lock 상태가 필요해지므로 :app에만 적용한다.
subprojects {
    if (name == "app") {
        dependencyLocking {
            lockAllConfigurations()
            ignoredDependencies.add("io.flutter:*")
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
