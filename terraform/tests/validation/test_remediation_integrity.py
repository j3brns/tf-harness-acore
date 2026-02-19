import os
import sys


def test_ssm_durability():
    print("[Test 1] Verifying SSM Durability in Foundation Module...")
    foundation_path = "terraform/modules/agentcore-foundation"
    for filename in os.listdir(foundation_path):
        if filename.endswith(".tf"):
            with open(os.path.join(foundation_path, filename), "r") as f:
                content = f.read()
                if 'data "external"' in content:
                    if filename == "gateway.tf" or filename == "identity.tf":
                        raise Exception(f"FAILED: 'data \"external\"' still exists in {filename}")

    with open("terraform/modules/agentcore-foundation/gateway.tf", "r") as f:
        content = f.read()
        if 'data "aws_ssm_parameter" "gateway_id"' not in content:
            raise Exception("FAILED: SSM data source missing in gateway.tf")

    print("  PASS: Brittle local state dependencies removed.")


def test_arch_logic():
    print("[Test 2] Verifying Architecture Logic in packaging.tf...")
    with open("terraform/modules/agentcore-runtime/packaging.tf", "r") as f:
        content = f.read()
        if 'PLATFORM="manylinux2014_x86_64"' not in content:
            raise Exception("FAILED: Default platform logic missing")
        if 'if [ "${var.lambda_architecture}" == "arm64" ]' not in content:
            raise Exception("FAILED: ARM64 architecture check missing")
        if 'PLATFORM="manylinux2014_aarch64"' not in content:
            raise Exception("FAILED: ARM64 platform logic missing")
    print("  PASS: Architecture-aware platform selection logic verified in code.")


def test_zip_exclusions():
    print("[Test 3] Verifying Hardened Zip Exclusions...")
    with open("terraform/modules/agentcore-runtime/packaging.tf", "r") as f:
        content = f.read()
        required_exclusions = ["*.env*", "*.tfvars*", ".terraform/*", ".venv/*", "venv/*", "tests/*", "node_modules/*"]
        for exc in required_exclusions:
            if exc not in content:
                raise Exception(f"FAILED: Exclusion pattern '{exc}' missing from packaging.tf")
    print("  PASS: Hardened zip exclusion patterns verified in code.")


def test_runtime_output_dir_creation():
    print("[Test 4] Verifying runtime module creates local .terraform output directory...")

    with open("terraform/modules/agentcore-runtime/runtime.tf", "r") as f:
        runtime_content = f.read()
        if 'mkdir -p "${path.module}/.terraform"' not in runtime_content:
            raise Exception("FAILED: runtime.tf does not create .terraform output directory before file writes")

    with open("terraform/modules/agentcore-runtime/inference_profile.tf", "r") as f:
        profile_content = f.read()
        if 'mkdir -p "${path.module}/.terraform"' not in profile_content:
            raise Exception(
                "FAILED: inference_profile.tf does not create .terraform output directory before file writes"
            )

    print("  PASS: Runtime/inference profile local output directory creation is enforced.")


if __name__ == "__main__":
    try:
        test_ssm_durability()
        test_arch_logic()
        test_zip_exclusions()
        test_runtime_output_dir_creation()
        print("\nAll remediation integrity tests PASSED successfully.")
    except Exception as e:
        print("\nREMEDIATION TEST FAILED: " + str(e))
        sys.exit(1)
