-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Ctrl+S to save (disable terminal flow control with stty -ixon in shell rc so this works)
vim.keymap.set("n", "<C-s>", "<cmd>w<cr>", { desc = "Save" })
vim.keymap.set("i", "<C-s>", "<C-o><cmd>w<cr>", { desc = "Save" })
vim.keymap.set("v", "<C-s>", "<C-c><cmd>w<cr>", { desc = "Save" })
vim.keymap.set("i", "<M-BS>", "<C-w>", { noremap = true })
-- Move line down
vim.keymap.set("n", "<A-j>", ":m .+1<CR>==", { desc = "Move line down" })

-- Move line up
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==", { desc = "Move line up" })

-- Move selected lines down
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })

-- Move selected lines up
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })
