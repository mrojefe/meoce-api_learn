-- =====================================================================
-- Migration: Add Watchlist Sections
-- Description: Creates the watchlist_sections table to support TradingView-like
--              dividers/sections inside custom watchlists. Updates watchlist_items
--              to reference the new sections.
-- =====================================================================

CREATE TABLE IF NOT EXISTS watchlist_sections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    watchlist_id UUID NOT NULL REFERENCES watchlists(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_collapsed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE watchlist_items
ADD COLUMN section_id UUID REFERENCES watchlist_sections(id) ON DELETE SET NULL,
ALTER COLUMN sort_order SET DEFAULT 0;

CREATE INDEX idx_watchlist_items_section_id ON watchlist_items(section_id);
