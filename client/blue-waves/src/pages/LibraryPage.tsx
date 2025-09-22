import { createSignal, createResource, useContext, For, Show, Suspense, Signal } from "solid-js";
import { A } from "@solidjs/router";
import { openDB } from "idb";
import { getToken } from "../utils/token";
import { AuthContext } from "../index.tsx";
import AddMusicModal from "../components/AddMusicModal.tsx";
import UpdateMusicModal from "../components/UpdateMusicModal.tsx";

const LibraryPage = () => {
    const [showAddMusicModal, setShowAddMusicModal] = createSignal(false);
    const [showUpdateMusicModal, setShowUpdateMusicModal] = createSignal(false);
    const [selectedMusicId, setSelectedMusicId] = createSignal("");
    const [coverArtUrl, setCoverArtUrl] = createSignal("");

    const [fetchCoverArtLoading, setFetchCoverArtLoading] = createSignal(false);

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const fetchMusicEntries = async () => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Get music entries
        const response = await fetch("http://localhost:8080/api/v1/users/music", {
            headers: { "Authorization": `Bearer ${token()}` }
        });

        if (response.ok) {
            return await response.json();
        } else if (response.status === 401) {
            setToken(await getToken());
            return await fetchMusicEntries();
        }
    };

    const [musicEntries, modifyMusicEntries] = createResource(fetchMusicEntries);

    const fetchCoverArt = async () => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        setFetchCoverArtLoading(true);
        // Open music database
        const db = await openDB("musicFileDB", 1, {
            upgrade(database) {
                database.createObjectStore("musicFiles", { keyPath: "music_id" });
                database.createObjectStore("coverArtFiles", { keyPath: "music_id" });
            },
        });

        // Check music database for a cached value
        const coverArtFileEntry = await db.get("coverArtFiles", selectedMusicId());
        if (coverArtFileEntry !== undefined) {
            // If a cached value exists perform a conditional request
            const response = await fetch(`http://localhost:8080/api/v1/users/music/${selectedMusicId()}/cover-art`, {
                headers: {
                    "Authorization": `Bearer ${token()}`,
                    "If-Modified-Since": coverArtFileEntry["last_modified"]
                }
            });

            if (response.ok) {
                // Cache miss: decode new data and update cache
                const imageBuffer = await response.arrayBuffer();
                const blob = new Blob([imageBuffer])
                const url = window.URL.createObjectURL(blob);

                await db.put("coverArtFiles", {music_id: selectedMusicId(), image_buffer: imageBuffer, last_modified: response.headers.get("Last-Modified")});

                setCoverArtUrl(url);
            } else if (response.status === 304) {
                const blob = new Blob([coverArtFileEntry["image_buffer"]]);
                const url = window.URL.createObjectURL(blob);
                setCoverArtUrl(url);
            } else if (response.status === 401) {
                setToken(await getToken());
                await fetchCoverArt();
            }

        } else {
            // If no cached value exists perform a normal request for the cover art file
            const response = await fetch(`http://localhost:8080/api/v1/users/music/${selectedMusicId()}/cover-art`, {
                headers: { "Authorization": `Bearer ${token()}` }
            });

            if (response.ok) {
                // Decode data as an image
                const imageBuffer = await response.arrayBuffer();
                const blob = new Blob([imageBuffer])
                const url = window.URL.createObjectURL(blob);

                // Cache cover art file for later requests
                await db.put("coverArtFiles", {music_id: selectedMusicId(), image_buffer: imageBuffer, last_modified: response.headers.get("Last-Modified")});

                setCoverArtUrl(url);
            } else if (response.status === 401) {
                setToken(await getToken());
                await fetchCoverArt();
            }
        }
        setFetchCoverArtLoading(false);
    }

    const preloadCoverArt = (musicId: string) => {
        if (musicId !== selectedMusicId()) {
            setSelectedMusicId(musicId);
            fetchCoverArt();
        }
    }

    return (
        <div class="flex">
            <div class="flex flex-col w-1/5 h-screen border-2">
                <nav class="flex flex-col items-center p-6">
                    <A href="/home" class="text-2xl font-medium m-6">Home</A>
                    <A href="/library" class="text-2xl font-medium m-6">Library</A>
                    <A href="/playlists" class="text-2xl font-medium m-6">Playlists</A>
                </nav>
            </div>
            <div class="flex flex-col w-4/5">
                <h1 class="text-3xl font-semibold mt-16 mb-4">Your Library</h1>
                <button class="rounded w-24 h-10 border-2 my-2" onClick={() => setShowAddMusicModal(true)}>Add Music</button>
                <hr class="border my-2"/>
                <Suspense>
                    <For each={musicEntries()}>
                        {(musicEntry) => (
                            <div class="flex justify-between items-center h-16 w-auto my-2 border-2">
                                <A href={musicEntry["music_id"]}>
                                    <div>
                                        <h2 class="text-lg font-semibold">{musicEntry["title"]}</h2>
                                        <h3 class="text-lg">{musicEntry["artist"]}</h3>
                                    </div>
                                </A>
                                <button class="rounded w-10 h-7 border-2 m-4" onMouseOver={() => preloadCoverArt(musicEntry["music_id"])} onClick={() => {setShowUpdateMusicModal(true)}}>...</button>
                            </div>
                        )}
                    </For>
                </Suspense>
            </div>
            <Show when={showUpdateMusicModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <UpdateMusicModal musicId={selectedMusicId} setMusicId={setSelectedMusicId} closeCallback={() => setShowUpdateMusicModal(false)} musicEntries={musicEntries} setMusicEntries={modifyMusicEntries.mutate} coverArtUrl={coverArtUrl} fetchCoverArtLoading={fetchCoverArtLoading}/>
                </div>
            </Show>
            <Show when={showAddMusicModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <AddMusicModal closeCallback={() => setShowAddMusicModal(false)} musicEntries={musicEntries} setMusicEntries={modifyMusicEntries.mutate}/>
                </div>
            </Show>
        </div>
    )
}

export default LibraryPage;
