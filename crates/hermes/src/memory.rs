use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct MemorySnapshot {
    #[serde(default)]
    pub global: String,
    #[serde(default)]
    pub entries: Vec<MemoryEntry>,
    #[serde(default)]
    pub project: Option<ProjectMemory>,
    #[serde(default)]
    pub project_snapshot: ProjectSnapshot,
    #[serde(default)]
    pub skills: Vec<SkillMemory>,
}

impl MemorySnapshot {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_entry(mut self, entry: MemoryEntry) -> Self {
        self.entries.push(entry);
        self
    }

    pub fn with_project_snapshot(mut self, project_snapshot: ProjectSnapshot) -> Self {
        self.project_snapshot = project_snapshot;
        self
    }

    pub fn is_empty(&self) -> bool {
        self.global.trim().is_empty()
            && self.entries.is_empty()
            && self
                .project
                .as_ref()
                .map(ProjectMemory::is_empty)
                .unwrap_or(true)
            && self.project_snapshot.is_empty()
            && self.skills.is_empty()
    }

    pub fn to_prompt_section(&self) -> String {
        if self.is_empty() {
            return "(none)".to_string();
        }

        let mut sections = Vec::new();
        if !self.global.trim().is_empty() {
            sections.push(format!("Global:\n{}", self.global.trim()));
        }
        if !self.entries.is_empty() {
            let entries = self
                .entries
                .iter()
                .map(|entry| format!("- {}: {}", entry.key.trim(), entry.value.trim()))
                .collect::<Vec<_>>()
                .join("\n");
            sections.push(format!("Entries:\n{entries}"));
        }
        if let Some(project) = &self.project {
            if !project.is_empty() {
                sections.push(format!(
                    "Project memory:\nPath: {}\nNotes: {}",
                    project.project_path.trim(),
                    project.notes.trim()
                ));
            }
        }
        if !self.project_snapshot.is_empty() {
            sections.push(format!(
                "Project snapshot:\n{}",
                indent(&self.project_snapshot.to_prompt_section())
            ));
        }
        if !self.skills.is_empty() {
            let skills = self
                .skills
                .iter()
                .map(|skill| format!("- {}: {}", skill.name.trim(), skill.description.trim()))
                .collect::<Vec<_>>()
                .join("\n");
            sections.push(format!("Skills:\n{skills}"));
        }
        sections.join("\n\n")
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MemoryEntry {
    pub key: String,
    pub value: String,
}

impl MemoryEntry {
    pub fn new(key: impl Into<String>, value: impl Into<String>) -> Self {
        Self {
            key: key.into(),
            value: value.into(),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ProjectMemory {
    pub project_path: String,
    #[serde(default)]
    pub notes: String,
}

impl ProjectMemory {
    pub fn is_empty(&self) -> bool {
        self.project_path.trim().is_empty() && self.notes.trim().is_empty()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SkillMemory {
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProjectFileSnapshot {
    pub path: String,
    pub summary: String,
    pub chars: usize,
}

impl ProjectFileSnapshot {
    pub fn new(path: impl Into<String>, summary: impl Into<String>, chars: usize) -> Self {
        Self {
            path: path.into(),
            summary: summary.into(),
            chars,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProjectSnapshot {
    pub root: Option<String>,
    pub summary: Option<String>,
    #[serde(default)]
    pub files: Vec<ProjectFileSnapshot>,
}

impl ProjectSnapshot {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_root(mut self, root: impl Into<String>) -> Self {
        self.root = Some(root.into());
        self
    }

    pub fn with_summary(mut self, summary: impl Into<String>) -> Self {
        self.summary = Some(summary.into());
        self
    }

    pub fn with_file(mut self, file: ProjectFileSnapshot) -> Self {
        self.files.push(file);
        self
    }

    pub fn is_empty(&self) -> bool {
        self.root.as_deref().unwrap_or("").trim().is_empty()
            && self.summary.as_deref().unwrap_or("").trim().is_empty()
            && self.files.is_empty()
    }

    pub fn to_prompt_section(&self) -> String {
        if self.is_empty() {
            return "(none)".to_string();
        }

        let mut lines = Vec::new();
        if let Some(root) = self
            .root
            .as_deref()
            .map(str::trim)
            .filter(|root| !root.is_empty())
        {
            lines.push(format!("Root: {root}"));
        }
        if let Some(summary) = self
            .summary
            .as_deref()
            .map(str::trim)
            .filter(|summary| !summary.is_empty())
        {
            lines.push(format!("Summary:\n{}", indent(summary)));
        }
        if !self.files.is_empty() {
            let files = self
                .files
                .iter()
                .map(|file| {
                    if file.summary.trim().is_empty() {
                        format!("- {} ({} chars)", file.path.trim(), file.chars)
                    } else {
                        format!(
                            "- {} ({} chars): {}",
                            file.path.trim(),
                            file.chars,
                            file.summary.trim()
                        )
                    }
                })
                .collect::<Vec<_>>()
                .join("\n");
            lines.push(format!("Files:\n{files}"));
        }
        lines.join("\n")
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct InMemoryStore {
    snapshot: MemorySnapshot,
}

impl InMemoryStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from_snapshot(snapshot: MemorySnapshot) -> Self {
        Self { snapshot }
    }

    pub fn snapshot(&self) -> &MemorySnapshot {
        &self.snapshot
    }

    pub fn snapshot_mut(&mut self) -> &mut MemorySnapshot {
        &mut self.snapshot
    }

    pub fn remember(&mut self, key: impl Into<String>, value: impl Into<String>) {
        let key = key.into();
        let value = value.into();
        if let Some(entry) = self
            .snapshot
            .entries
            .iter_mut()
            .find(|entry| entry.key == key)
        {
            entry.value = value;
        } else {
            self.snapshot.entries.push(MemoryEntry::new(key, value));
        }
    }

    pub fn clear(&mut self) {
        self.snapshot = MemorySnapshot::default();
    }
}

fn indent(value: &str) -> String {
    value
        .lines()
        .map(|line| format!("  {line}"))
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_memory_snapshot_detects_all_empty_fields() {
        assert!(MemorySnapshot::default().is_empty());
        assert!(!MemorySnapshot {
            global: "prefer concise answers".into(),
            ..Default::default()
        }
        .is_empty());
    }

    #[test]
    fn in_memory_store_updates_existing_entries() {
        let mut store = InMemoryStore::new();
        store.remember("goal", "extract runtime");
        store.remember("goal", "extract hermes runtime");

        assert_eq!(
            store.snapshot().entries,
            vec![MemoryEntry::new("goal", "extract hermes runtime")]
        );
    }

    #[test]
    fn project_snapshot_renders_for_prompts() {
        let snapshot = ProjectSnapshot::new()
            .with_root("/repo")
            .with_summary("runtime crate")
            .with_file(ProjectFileSnapshot::new("src/lib.rs", "public surface", 42));

        assert_eq!(
            snapshot.to_prompt_section(),
            "Root: /repo\nSummary:\n  runtime crate\nFiles:\n- src/lib.rs (42 chars): public surface"
        );
    }
}
