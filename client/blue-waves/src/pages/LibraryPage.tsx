import { createSignal, createResource, For, Show, Suspense } from "solid-js";
import { useNavigate, A } from "@solidjs/router";
import { api } from "../index.tsx";
import MusicModal from "../components/MusicModal.tsx";

const LibraryPage = () => {
    const [showMusicModal, setShowMusicModal] = createSignal(false);

    const navigate = useNavigate();

    const [token] = createResource(async () => {
        try {
            const tokenResponse = await api.get("users/token", { credentials: "include" }).json<{"access_token": string}>();
            return tokenResponse["access_token"];
        } catch (error) {
            navigate("/login");
        }
    });

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
                <button class="rounded border-2 my-2" onClick={() => setShowMusicModal(true)}>Add Music</button>
                <hr class="border my-2" />
                <Suspense>
                    <For each={musicEntries()}>
                        {(musicEntry) => (
                            <A href={musicEntry["music_id"]}>
                                <div class="h-16 w-auto my-2 border-2">
                                    <h2 class="text-lg font-semibold">{musicEntry["title"]}</h2>
                                    <h3 class="text-lg">{musicEntry["artist"]}</h3>
                                </div>
                            </A>
                        )}
                    </For>
                </Suspense>
            </div>
            <Show when={showMusicModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <MusicModal token={token() as string} closeCallback={() => setShowMusicModal(false)} musicEntries={musicEntries} setMusicEntries={modifyMusicEntries.mutate}/>
                </div>
            </Show>
        </div>
    )
}

export default LibraryPage;
