# Library tools and contextual search

The Library header retains its media icon/dropdown. Only the active view label
(Saved, Downloaded, Starred, or a folder name) sits below it. Search, filter, and
sort controls no longer occupy the content area.

The bottom-right hamburger opens Search, Views, Add, Sort, and Filter. Views and
Add expand into child arcs; the center becomes a back arrow. The selected category
moves toward the center while siblings retract, then children fan outward. The
root center closes the menu. Outside dismissal resets the menu, so reopening
always starts at the root. Reduced Motion skips movement and delays.

Views offers Saved, Downloaded, Starred, and Folders. Folders opens a picker.
Add offers Import and New folder. Sort and Filter use focused sheets with a Back
control returning to the tools menu. Filters narrow the chosen view by progress
or status and contain layout controls; they do not repeat the collection choices.

Search uses the same Spotlight interface as Browse. From Library it searches all
saved titles in the current profile, irrespective of the visible folder, media
mode, or filters. Its source choices come only from those saved titles. The local
repository makes no network requests. With no matches, Browse sources carries the
query to a new source search. Back restores the Library search and its results.
The bottom navigation's Find icon opens source search directly and has a muted
green circular background inside the existing floating navigation island.

Folder/star persistence and JSON import retain their prior behavior. Import only
supports the iOS Moku library.json format. Completed Download entries populate
Downloaded; the transfer service remains outside this UI change.

LibrarySearchTests covers saved-title search, source deduplication, mixed-media
sources, and local filtering. SearchModelTests covers cancellation, debounce, and
options. HeaderLayoutTests covers nested actions, back navigation, filter/view
separation, empty Library search, source handoff, query restoration, and Find.
SearchTests covers the existing global-search behavior.
