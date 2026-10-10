package com.example.demo;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicLong;

@RestController
@RequestMapping("/api")
public class NoteController {

    public record Note(long id, String text) {}

    public record NewNote(String text) {}

    // Хранение в памяти — для демо база не нужна
    private final List<Note> notes = new CopyOnWriteArrayList<>();
    private final AtomicLong ids = new AtomicLong();

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }

    @GetMapping("/notes")
    public List<Note> list() {
        return notes;
    }

    @PostMapping("/notes")
    @ResponseStatus(HttpStatus.CREATED)
    public Note add(@RequestBody NewNote body) {
        if (body == null || body.text() == null || body.text().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "text is required");
        }
        Note note = new Note(ids.incrementAndGet(), body.text().trim());
        notes.add(note);
        return note;
    }

    @DeleteMapping("/notes/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable long id) {
        if (!notes.removeIf(n -> n.id() == id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
    }
}
