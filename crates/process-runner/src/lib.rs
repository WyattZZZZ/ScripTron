use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Duration;
use thiserror::Error;
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::time::timeout;

#[derive(Debug, Error)]
pub enum RunnerError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Process timed out after {0}s")]
    Timeout(u64),
    #[error("Working directory does not exist: {0}")]
    BadWorkDir(PathBuf),
}

/// Configuration for a single process execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessConfig {
    pub command: String,
    pub args: Vec<String>,
    /// Defaults to the current directory if None.
    pub working_dir: Option<PathBuf>,
    /// Timeout in seconds. Defaults to 30.
    #[serde(default = "default_timeout")]
    pub timeout_secs: u64,
    /// Environment variables to inject (in addition to the parent env).
    #[serde(default)]
    pub env: Vec<(String, String)>,
}

fn default_timeout() -> u64 {
    30
}

impl ProcessConfig {
    pub fn new(command: impl Into<String>, args: impl IntoIterator<Item = impl Into<String>>) -> Self {
        Self {
            command: command.into(),
            args: args.into_iter().map(Into::into).collect(),
            working_dir: None,
            timeout_secs: 30,
            env: Vec::new(),
        }
    }

    pub fn with_working_dir(mut self, dir: impl Into<PathBuf>) -> Self {
        self.working_dir = Some(dir.into());
        self
    }

    pub fn with_timeout(mut self, secs: u64) -> Self {
        self.timeout_secs = secs;
        self
    }
}

/// The result of running a process.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
    pub timed_out: bool,
}

impl ProcessResult {
    pub fn success(&self) -> bool {
        self.exit_code == 0 && !self.timed_out
    }

    /// Combined output for display / LLM consumption.
    pub fn combined_output(&self) -> String {
        let mut out = self.stdout.clone();
        if !self.stderr.is_empty() {
            if !out.is_empty() {
                out.push('\n');
            }
            out.push_str(&self.stderr);
        }
        if self.timed_out {
            out.push_str("\n[Process timed out]");
        }
        out
    }
}

pub struct ProcessRunner;

impl ProcessRunner {
    pub fn new() -> Self {
        ProcessRunner
    }

    /// Run a process and capture its output.
    pub async fn run(&self, config: ProcessConfig) -> Result<ProcessResult, RunnerError> {
        if let Some(ref wd) = config.working_dir {
            if !wd.exists() {
                return Err(RunnerError::BadWorkDir(wd.clone()));
            }
        }

        let mut cmd = Command::new(&config.command);
        cmd.args(&config.args);

        // Stdout / stderr captured as pipes
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::piped());

        if let Some(ref wd) = config.working_dir {
            cmd.current_dir(wd);
        }

        for (k, v) in &config.env {
            cmd.env(k, v);
        }

        let deadline = Duration::from_secs(config.timeout_secs);

        let result = timeout(deadline, async {
            let mut child = cmd.spawn()?;

            // Read stdout and stderr concurrently via the piped handles
            let stdout_handle = child.stdout.take();
            let stderr_handle = child.stderr.take();

            let (stdout_bytes, stderr_bytes) = tokio::join!(
                async {
                    let mut buf = Vec::new();
                    if let Some(mut h) = stdout_handle {
                        let _ = h.read_to_end(&mut buf).await;
                    }
                    buf
                },
                async {
                    let mut buf = Vec::new();
                    if let Some(mut h) = stderr_handle {
                        let _ = h.read_to_end(&mut buf).await;
                    }
                    buf
                }
            );

            let status = child.wait().await?;
            let exit_code = status.code().unwrap_or(-1);

            Ok::<ProcessResult, std::io::Error>(ProcessResult {
                stdout: String::from_utf8_lossy(&stdout_bytes).into_owned(),
                stderr: String::from_utf8_lossy(&stderr_bytes).into_owned(),
                exit_code,
                timed_out: false,
            })
        })
        .await;

        match result {
            Ok(Ok(r)) => Ok(r),
            Ok(Err(e)) => Err(RunnerError::Io(e)),
            Err(_) => Ok(ProcessResult {
                stdout: String::new(),
                stderr: String::new(),
                exit_code: -1,
                timed_out: true,
            }),
        }
    }
}

impl Default for ProcessRunner {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn runs_echo() {
        let runner = ProcessRunner::new();
        let result = runner
            .run(ProcessConfig::new("echo", ["hello world"]))
            .await
            .unwrap();
        assert!(result.success());
        assert!(result.stdout.contains("hello world"));
    }

    #[tokio::test]
    async fn captures_stderr() {
        let runner = ProcessRunner::new();
        let result = runner
            .run(ProcessConfig::new("sh", ["-c", "echo err >&2; exit 1"]))
            .await
            .unwrap();
        assert!(!result.success());
        assert!(result.stderr.contains("err"));
    }

    #[tokio::test]
    async fn times_out() {
        let runner = ProcessRunner::new();
        let result = runner
            .run(ProcessConfig::new("sleep", ["60"]).with_timeout(1))
            .await
            .unwrap();
        assert!(result.timed_out);
    }
}
