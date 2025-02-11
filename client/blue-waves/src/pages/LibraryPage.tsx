import { createSignal, createResource, For, Show, Suspense } from "solid-js";
import { createAsync, A } from "@solidjs/router";
import { openDB } from "idb";
import { HTTPError } from "ky";
import { getToken } from "../utils/token";
import { api } from "../index.tsx";
import AddMusicModal from "../components/AddMusicModal.tsx";
import UpdateMusicModal from "../components/UpdateMusicModal.tsx";

const LibraryPage = () => {
    const [showAddMusicModal, setShowAddMusicModal] = createSignal(false);
    const [showUpdateMusicModal, setShowUpdateMusicModal] = createSignal(false);
    const [selectedMusicId, setSelectedMusicId] = createSignal("");
    const [coverArtUrl, setCoverArtUrl] = createSignal("");

    const [fetchCoverArtLoading, setFetchCoverArtLoading] = createSignal(false);

    const token = createAsync(() => getToken());

    const [musicEntries, modifyMusicEntries] = createResource(token, async () => {
        // Get music entries
        const musicResponse = await api.get("users/music", {
            headers: {
                "Authorization": `Bearer ${token()}`
            }
        }).json<{"music": {"music_id": string, "title": string, "artist": string}[]}>();

        return musicResponse["music"]
    });

    const fetchCoverArt = async () => {
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
            try {
                const musicArtResponse = await api.get(`users/music/${selectedMusicId()}/cover-art`, {
                    headers: {
                        "Authorization": `Bearer ${token()}`,
                        "If-Modified-Since": coverArtFileEntry["last_modified"]
                    }
                })

                // Cache miss: decode new data and update cache
                const imageBuffer = await musicArtResponse.arrayBuffer();
                const blob = new Blob([imageBuffer])
                const url = window.URL.createObjectURL(blob);

                await db.put("coverArtFiles", {music_id: selectedMusicId(), image_buffer: imageBuffer, last_modified: musicArtResponse.headers.get("Last-Modified")});

                setCoverArtUrl(url);
            } catch (e) {
                const httpError = e as HTTPError;

                // Cache hit: reuse saved data
                if (httpError.response.status === 304) {
                    const blob = new Blob([coverArtFileEntry["image_buffer"]]);
                    const url = window.URL.createObjectURL(blob);
                    setCoverArtUrl(url);
                }
            }
        } else {
            // If no cached value exists perform a normal request for the cover art file
            const musicArtResponse = await api.get(`users/music/${selectedMusicId()}/cover-art`, {
                headers: {
                    "Authorization": `Bearer ${token()}`
                }
            });

            // Decode data as an image
            const imageBuffer = await musicArtResponse.arrayBuffer();
            const blob = new Blob([imageBuffer])
            const url = window.URL.createObjectURL(blob);

            // Cache cover art file for later requests
            await db.put("coverArtFiles", {music_id: selectedMusicId(), image_buffer: imageBuffer, last_modified: musicArtResponse.headers.get("Last-Modified")});

            setCoverArtUrl(url);
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
        <div>
            <div>
                <h1 class="text-2xl font-semibold my-4">Your Library</h1>
                <button class="rounded border-2 my-2" onClick={() => setShowAddMusicModal(true)}>Add Music</button>
                <hr class="border my-2" />
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
                    <UpdateMusicModal token={token() as string} musicId={selectedMusicId} setMusicId={setSelectedMusicId} closeCallback={() => setShowUpdateMusicModal(false)} musicEntries={musicEntries} setMusicEntries={modifyMusicEntries.mutate} coverArtUrl={coverArtUrl} fetchCoverArtLoading={fetchCoverArtLoading}/>
                </div>
            </Show>
            <Show when={showAddMusicModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <AddMusicModal token={token() as string} closeCallback={() => setShowAddMusicModal(false)} musicEntries={musicEntries} setMusicEntries={modifyMusicEntries.mutate}/>
                </div>
            </Show>
        </div>
    )
}

export default LibraryPage;
