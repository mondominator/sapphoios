# Android Parity Design Plan

## Priority 1: Navigation (Replace TabView with Top Bar)
- Replace bottom TabView with custom top bar: [Logo] [Home] [Library] [Search] [Avatar]
- Avatar dropdown: Profile, Downloads, Admin, Logout, versions
- Mini player stays at bottom as sole bottom element

## Priority 2: Home Screen Cards (Cover-Only)
- Remove title/author text below cards — cover image only
- Resize cards per section: Continue Listening 160pt, Up Next/Recently Added 140pt, Listen Again 110pt
- Section title sizes: Continue Listening 20pt, Up Next/Recently Added 16pt, Listen Again 14pt

## Priority 3: Detail Screen Polish
- Increase cover to 320pt
- Add reading list bookmark overlay on cover (top-right)
- Play button: green background when stopped, blue when playing
- Add Files section (expandable)
- Make Author/Series metadata tappable (navigate to filtered library)

## Priority 4: Library Categories Hub
- Replace tab pills with Android-style categories hub
- Large hero card for Series, medium cards for Authors/Genres/Collections/Reading List
- All Books card at bottom
- Each category drills into sub-view with back navigation

## Priority 5: Mini Player Enhancement
- Add interactive seek on progress bar (tap + drag)
- Play button color: green when playing, blue when paused
- Add time display (elapsed / total) with animated pulse when playing
- Use Replay10/Forward10 icons

## Priority 6: Player Fine-Tuning
- Already mostly done
- Playing animation bars at bottom when playing

## Priority 7: Search Polish
- Match Android's search bar styling
- Skeleton loading state
