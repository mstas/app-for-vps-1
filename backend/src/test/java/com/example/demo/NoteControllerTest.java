package com.example.demo;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(NoteController.class)
class NoteControllerTest {

    @Autowired
    MockMvc mvc;

    @Test
    void healthIsOk() throws Exception {
        mvc.perform(get("/api/health"))
           .andExpect(status().isOk())
           .andExpect(jsonPath("$.status").value("ok"));
    }

    @Test
    void addAndListNotes() throws Exception {
        mvc.perform(post("/api/notes").contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"hello\"}"))
           .andExpect(status().isCreated())
           .andExpect(jsonPath("$.text").value("hello"));
        mvc.perform(get("/api/notes"))
           .andExpect(status().isOk())
           .andExpect(jsonPath("$[0].text").value("hello"));
    }

    @Test
    void rejectsEmptyText() throws Exception {
        mvc.perform(post("/api/notes").contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"  \"}"))
           .andExpect(status().isBadRequest());
    }
}
