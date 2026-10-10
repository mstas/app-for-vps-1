const statusEl = document.getElementById("status");
const listEl = document.getElementById("list");
const emptyEl = document.getElementById("empty");
const form = document.getElementById("form");
const input = document.getElementById("text");

async function checkHealth() {
  try {
    const res = await fetch("/api/health");
    const data = await res.json();
    statusEl.textContent = "API: " + data.status;
    statusEl.className = "status ok";
  } catch {
    statusEl.textContent = "API недоступен";
    statusEl.className = "status err";
  }
}

function render(notes) {
  listEl.innerHTML = "";
  emptyEl.hidden = notes.length > 0;
  for (const note of notes) {
    const li = document.createElement("li");
    const span = document.createElement("span");
    span.textContent = note.text;
    const del = document.createElement("button");
    del.textContent = "✕";
    del.title = "Удалить";
    del.onclick = async () => {
      await fetch(`/api/notes/${note.id}`, { method: "DELETE" });
      load();
    };
    li.append(span, del);
    listEl.append(li);
  }
}

async function load() {
  try {
    const res = await fetch("/api/notes");
    render(await res.json());
  } catch {
    render([]);
  }
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  await fetch("/api/notes", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text }),
  });
  input.value = "";
  load();
});

checkHealth();
load();
