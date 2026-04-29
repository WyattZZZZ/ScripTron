use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ParseError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Invalid cell header at line {line}: {msg}")]
    InvalidHeader { line: usize, msg: String },
    #[error("Unclosed cell starting at line {0}")]
    UnclosedCell(usize),
}

/// A single cell in a .tron file.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TronCell {
    /// Whether this cell is executed by the agent.
    pub run: bool,
    /// The cell's content (markdown or natural language instruction).
    pub content: String,
}

/// A parsed .tron file: an ordered list of cells.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronFile {
    pub path: PathBuf,
    pub cells: Vec<TronCell>,
}

/// The input payload handed to the agent loop.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronTask {
    /// Ordered list of instructions from `run: true` cells.
    pub instructions: Vec<String>,
    /// Static context from `run: false` cells (notes / docs the agent can read).
    pub context: Vec<String>,
    pub project_path: PathBuf,
}

impl TronFile {
    pub fn build_task(&self, project_path: impl Into<PathBuf>) -> TronTask {
        let mut instructions = Vec::new();
        let mut context = Vec::new();
        for cell in &self.cells {
            let trimmed = cell.content.trim().to_string();
            if trimmed.is_empty() {
                continue;
            }
            if cell.run {
                instructions.push(trimmed);
            } else {
                context.push(trimmed);
            }
        }
        TronTask {
            instructions,
            context,
            project_path: project_path.into(),
        }
    }
}

/// Parse a `.tron` file from disk.
pub fn parse_file(path: impl AsRef<Path>) -> Result<TronFile, ParseError> {
    let raw = std::fs::read_to_string(path.as_ref())?;
    let cells = parse_str(&raw)?;
    Ok(TronFile {
        path: path.as_ref().to_path_buf(),
        cells,
    })
}

/// Parse `.tron` content from a string (useful for tests and the editor).
pub fn parse_str(src: &str) -> Result<Vec<TronCell>, ParseError> {
    let mut cells: Vec<TronCell> = Vec::new();
    let lines: Vec<&str> = src.lines().collect();
    let mut i = 0;

    while i < lines.len() {
        let line = lines[i];

        // Skip blank lines between cells
        if line.trim().is_empty() {
            i += 1;
            continue;
        }

        // Opening header: ---run: true--- or ---run: false---
        if let Some(run) = parse_header(line) {
            let start_line = i;
            i += 1;

            // Collect body until closing ---
            let mut body_lines: Vec<&str> = Vec::new();
            let mut closed = false;
            while i < lines.len() {
                if lines[i].trim() == "---" {
                    closed = true;
                    i += 1;
                    break;
                }
                body_lines.push(lines[i]);
                i += 1;
            }

            if !closed {
                return Err(ParseError::UnclosedCell(start_line + 1));
            }

            // Trim trailing blank lines from body
            while body_lines.last().map(|l| l.trim().is_empty()).unwrap_or(false) {
                body_lines.pop();
            }

            cells.push(TronCell {
                run,
                content: body_lines.join("\n"),
            });
        } else {
            // Bare content outside a cell header — treat as a static note cell
            let mut body_lines = vec![line];
            i += 1;
            while i < lines.len() {
                let next = lines[i];
                if parse_header(next).is_some() || next.trim() == "---" {
                    break;
                }
                body_lines.push(next);
                i += 1;
            }
            let content = body_lines.join("\n").trim().to_string();
            if !content.is_empty() {
                cells.push(TronCell { run: false, content });
            }
        }
    }

    Ok(cells)
}

/// Serialise cells back to `.tron` format.
pub fn serialize(cells: &[TronCell]) -> String {
    let mut out = String::new();
    for cell in cells {
        let flag = if cell.run { "true" } else { "false" };
        out.push_str(&format!("---run: {}---\n", flag));
        out.push_str(&cell.content);
        if !cell.content.ends_with('\n') {
            out.push('\n');
        }
        out.push_str("---\n\n");
    }
    out
}

// ---run: true--- or ---run: false---
fn parse_header(line: &str) -> Option<bool> {
    let s = line.trim();
    if s == "---run: true---" {
        Some(true)
    } else if s == "---run: false---" {
        Some(false)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        // Canonical format: each cell ends with ---\n\n (trailing blank line included)
        let src = "---run: true---\nLook at all the CSV files and summarise them.\n---\n\n---run: false---\n## Notes\nRemember to check Q2 figures.\n---\n\n";
        let cells = parse_str(src).unwrap();
        assert_eq!(cells.len(), 2);
        assert!(cells[0].run);
        assert!(!cells[1].run);
        assert_eq!(serialize(&cells), src);
    }

    #[test]
    fn bare_content_becomes_static_cell() {
        let src = "Just a note without a header\n";
        let cells = parse_str(src).unwrap();
        assert_eq!(cells.len(), 1);
        assert!(!cells[0].run);
    }

    #[test]
    fn build_task_splits_correctly() {
        let cells = vec![
            TronCell { run: true, content: "Instruction one".into() },
            TronCell { run: false, content: "Context note".into() },
            TronCell { run: true, content: "Instruction two".into() },
        ];
        let file = TronFile { path: PathBuf::from("test.tron"), cells };
        let task = file.build_task("/tmp");
        assert_eq!(task.instructions, vec!["Instruction one", "Instruction two"]);
        assert_eq!(task.context, vec!["Context note"]);
    }
}
