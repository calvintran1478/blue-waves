import { createResource, useContext, For, Resource, Signal, Setter, Suspense } from "solid-js";
import { AuthContext } from "../index.tsx";
import { getToken } from "../utils/token";

// Expected fields for each music entry
interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const AddPlaylistMusicModal = (props: { closeCallback: () => void, playlistId: string, playlistMusic: Resource<MusicEntry[]>, setPlaylistMusic: Setter<MusicEntry[] | undefined>}) => {

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const addPlaylistMusic = async (event: Event) => {
        // Prevent refresh
        event.preventDefault();

        const nodeList = document.querySelectorAll("input[type='checkbox']");
        let selectedMusicId = "";
        nodeList.forEach((node) => {
            if ((node as HTMLInputElement).checked) {
                selectedMusicId = node.id;
            }
        })

        const response = await fetch(`http://localhost:8080/api/v1/users/playlists/${props.playlistId}/music`, {
            method: "POST",
            headers: { "Authorization": `Bearer ${token()}` },
            body: selectedMusicId
        });

        if (response.ok) {
            // Add music entry to list
            const newPlaylistMusic = [...props.playlistMusic()!];
            newPlaylistMusic!.push(newMusic().find((musicEntry: MusicEntry) => musicEntry["music_id"] === selectedMusicId));
            props.setPlaylistMusic(newPlaylistMusic);

            // Close modal
            props.closeCallback();
        } else if (response.status === 401) {
            setToken(await getToken());
            await addPlaylistMusic(event);
        }
    }

    // Search for music tracks not in playlist
    const fetchNewMusic = async () => {
        // Get music entries
        const response = await fetch("http://localhost:8080/api/v1/users/music", {
            headers: { "Authorization": `Bearer ${token()}` }
        });

        if (response.ok) {
            const musicEntries = await response.json();
            const musicIdsToExclude = props.playlistMusic()!.map((musicEntry) => musicEntry["music_id"]);
            return musicEntries.filter((musicEntry: MusicEntry) => !musicIdsToExclude.includes(musicEntry["music_id"]));
        } else if (response.status === 401) {
            setToken(await getToken());
            return await fetchNewMusic();
        }
    }

    const [newMusic] = createResource(fetchNewMusic); 

    return (
        <div class="p-6 bg-white" style="width: 40rem; height: 28rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback}>close</button>
            </div>
            <form onSubmit={addPlaylistMusic} class="flex flex-col items-center">
                <h2 class="text-2xl font-medium">Select music tracks to add</h2>
                <div class="w-96 h-64 m-4 border overflow-auto">
                    <Suspense>
                        <For each={newMusic()}>
                            {(musicEntry) => (
                                <div class="my-4">
                                    <input class="w-4 h-4 mx-4" type="checkbox" id={musicEntry["music_id"]}/>
                                    <label class="text-lg">{musicEntry["title"]} - {musicEntry["artist"]}</label>
                                </div>
                            )}
                        </For>
                    </Suspense>
                </div>
                <button class="inline-flex items-center border-2 rounded p-3 bg-neutral-400">
                    <span class="mr-2">Add music</span>
                </button>
            </form>
        </div>
    )
}

export default AddPlaylistMusicModal;
