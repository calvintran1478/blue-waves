import { createSignal, createResource, For, Show, Suspense } from "solid-js";
import { createAsync, A } from "@solidjs/router";
import { getToken } from "../utils/token";
import { api } from "../index.tsx";
import AddMusicModal from "../components/AddMusicModal.tsx";
import UpdateMusicModal from "../components/UpdateMusicModal.tsx";

const LibraryPage = () => {
    const [showAddMusicModal, setShowAddMusicModal] = createSignal(false);
    const [showUpdateMusicModal, setShowUpdateMusicModal] = createSignal(false);
    const [selectedMusicId, setSelectedMusicId] = createSignal("");

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
                                <button class="rounded w-10 h-7 border-2 m-4" onClick={() => {setSelectedMusicId(musicEntry["music_id"]); setShowUpdateMusicModal(true)}}>...</button>
                            </div>
                        )}
                    </For>
                </Suspense>
            </div>
            <Show when={showUpdateMusicModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <UpdateMusicModal token={token() as string} music_id={selectedMusicId} closeCallback={() => setShowUpdateMusicModal(false)} musicEntries={musicEntries} setMusicEntries={modifyMusicEntries.mutate}/>
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
