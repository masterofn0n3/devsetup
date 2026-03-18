-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Ctrl+S to save (disable terminal flow control with stty -ixon in shell rc so this works)
vim.keymap.set("n", "<C-s>", "<cmd>w<cr>", { desc = "Save" })
vim.keymap.set("i", "<C-s>", "<C-o><cmd>w<cr>", { desc = "Save" })
vim.keymap.set("v", "<C-s>", "<C-c><cmd>w<cr>", { desc = "Save" })
vim.keymap.set("i", "<M-BS>", "<C-w>", { noremap = true })
