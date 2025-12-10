from __future__ import annotations
from pathlib import Path
import tempfile
import subprocess


def main() -> None:
    current_repo = GitRepository(get_repository_root_directory())
    with tempfile.TemporaryDirectory() as _tempdir:
        tempdir = Path(_tempdir)
        temp_repo = current_repo.clone_to(tempdir)
        update_branch = "update-flake-inputs"
        github_remote = "github-temp"
        temp_repo.create_remote(
            name=github_remote,
            url="git@github.com:ida-arbeitszeit/workers-control-deployment.git",
        )
        temp_repo.disable_detached_head_advice()
        temp_repo.fetch(github_remote)
        temp_repo.checkout_branch(f"{github_remote}/development")
        temp_repo.checkout_new_branch(update_branch)
        flake = NixFlake(tempdir)
        flake.update_inputs()
        assert temp_repo.diff().has_changes
        assert flake.run_checks(2).is_success
        temp_repo.add_changes()
        temp_repo.commit_changes("Update flake inputs")
        temp_repo.push_branch(branch=update_branch, remote=github_remote, force=True)


def get_repository_root_directory() -> Path:
    return Path(__file__).parent


class DiffResult:
    def __init__(self, exit_code: int) -> None:
        self.exit_code = exit_code

    @property
    def has_changes(self) -> bool:
        return self.exit_code == 1


class FlakeCheckResult:
    def __init__(self, exit_code: int) -> None:
        self.exit_code = exit_code

    @property
    def is_success(self) -> bool:
        return self.exit_code == 0


class GitRepository:
    def __init__(self, directory: Path) -> None:
        self._directory = directory

    def checkout_new_branch(self, name: str) -> None:
        subprocess.run(["git", "checkout", "-b", name], check=True, cwd=self._directory)

    def create_remote(self, *, name: str, url: str) -> None:
        subprocess.run(
            ["git", "remote", "add", name, url], check=True, cwd=self._directory
        )

    def push_branch(self, *, branch: str, remote: str, force: bool = False) -> None:
        command = ["git", "push"] + (["-f"] if force else []) + [remote, branch]
        subprocess.run(command, check=True, cwd=self._directory)

    def commit_changes(self, message: str) -> None:
        subprocess.run(
            ["git", "commit", "-m", message], check=True, cwd=self._directory
        )

    def add_changes(self) -> None:
        subprocess.run(["git", "add", "."], cwd=self._directory)

    def checkout_branch(self, name: str) -> None:
        subprocess.run(["git", "checkout", name], cwd=self._directory, check=True)

    def fetch(self, remote: str) -> None:
        subprocess.run(["git", "fetch", remote], cwd=self._directory, check=True)

    def clone_to(self, directory: Path) -> GitRepository:
        subprocess.run(["git", "clone", "--", self._directory, directory], check=True)
        return GitRepository(directory)

    def diff(self) -> DiffResult:
        result = subprocess.run(["git", "diff", "--exit-code"], cwd=self._directory)
        return DiffResult(
            exit_code=result.returncode,
        )

    def disable_detached_head_advice(self) -> None:
        subprocess.run(
            ["git", "config", "advice.detachedHead", "false"],
            cwd=self._directory,
            check=True,
        )


class NixFlake:
    def __init__(self, directory: Path) -> None:
        self._directory = directory

    def update_inputs(self) -> None:
        subprocess.run(["nix", "flake", "update"], cwd=self._directory, check=True)

    def run_checks(self, jobs: int) -> FlakeCheckResult:
        result = subprocess.run(
            ["nix", "flake", "check", "--print-build-logs", "-j", str(jobs)],
            cwd=self._directory,
        )
        return FlakeCheckResult(exit_code=result.returncode)


if __name__ == "__main__":
    main()
