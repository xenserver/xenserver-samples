# XenServer.NET Usage Examples

## Overview

The XenServer.NET examples provide practical demonstrations of interacting with XenServer infrastructure using the XenServer.NET SDK. These examples are written as a Microsoft Visual Studio solution and are designed to showcase various functionalities and features of the XenServer platform.

### Included Examples

- **GetVariousRecords**: This example logs into a XenServer host and retrieves information about hosts, storage, and virtual machines. It offers insights into the current state and configuration of the XenServer environment.

- **VmPowerStates**: This example demonstrates how to manage the power states of a virtual machine (VM) on a XenServer host. It logs into a XenServer host, locates a specified VM, and transitions it through different power states. Note that this example requires a pre-existing VM to be installed and available for manipulation.

## How to Run the Examples

To run the XenServer.NET examples, follow these steps:

1. **Install Dependencies**:
   - Ensure that the XenServer.NET NuGet package is installed in your project. You can download the stable release from [xenserver.com/downloads](xenserver.com/downloads).
   - Alternatively, if you prefer using an unstable prerelease version, you can fetch it from the [Xen-API repository's release page](https://github.com/xapi-project/xen-api/releases).

2. **Open Solution in Visual Studio**:
   - Open the `XenSdkSample.sln` solution file in Microsoft Visual Studio 2022.

3. **Compile the Solution**:
   - Build the solution within Visual Studio to compile the example projects.

4. **Run the Examples**:
   - Run the compiled application from the command line, providing the required parameters:
     ```
     .\XenSdkSample.exe <host> <username> <password>
     ```
   Replace the placeholders (`<host>`, `<username>`, `<password>`) with the following:
      - `<host>`: The URL of the XenServer host in the format `https://host[:port]`.
      - `<username>`: A valid user account on the XenServer host (e.g., root).
      - `<password>`: The password associated with the specified username.

By following these instructions, you can explore and utilize the XenServer.NET examples to gain insights into working with XenServer infrastructure and managing virtualized environments effectively.
