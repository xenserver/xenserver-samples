#!groovy

@Library(['PacmanSharedLibrary', "xs-sdk-samples-pipeline@v1.0"])
import com.xenserver.pipeline.sdksamples.*

properties([
    [
        $class: 'BuildDiscarderProperty',
        strategy: [$class: 'LogRotator', numToKeepStr: '10', artifactNumToKeepStr: '10']
    ]
])

def SDK_URL = "master/24.32.0/1.xs8/76/"

def builder = null
def globals = globals()

try {
    builder = new Build(globals, SDK_URL)
    runPipeline(builder)
    currentBuild.result = 'SUCCESS'
}
catch (Throwable ex) {
    currentBuild.result = 'FAILURE'
    throw ex
}
finally {
    buildComplete(builder)
}
