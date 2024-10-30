import { createSignal, Resource, Setter, Show } from "solid-js";
import { createQuery } from "@tanstack/solid-query";
import { api } from "../index.tsx";
import LoadingSpinner from "../components/LoadingSpinner";

// Expected fields for each music entry
interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const MusicModal = (props: { token: string, closeCallback: () => void, musicEntries: Resource<MusicEntry[]>, setMusicEntries: Setter<MusicEntry[] | undefined>}) => {
    const [title, setTitle] = createSignal("");
    const [artist, setArtist] = createSignal("");

    let musicInput!: HTMLInputElement;

    const addMusicQuery = createQuery(() => ({
        queryKey: ["AddMusic"],
        queryFn: async () => {
            // Create form data
            const data = new FormData();
            data.append("title", title());
            data.append("artist", artist());
            data.append("file", musicInput.files![0]);

            // Add music
            const addMusicResponse = await api.post("users/music", {
                headers: {
                    "Authorization": `Bearer ${props.token}`
                },
                body: data
            }).json<MusicEntry>();

            // Add music entry to list
            const newMusicEntries = [...props.musicEntries()!];
            newMusicEntries!.push({"music_id": addMusicResponse["music_id"], "title": addMusicResponse["title"], "artist": addMusicResponse["artist"]});
            props.setMusicEntries(newMusicEntries);

            // Close modal
            props.closeCallback();

            return null;
        }
    }));

    const addMusic = (event: Event) => {
        event.preventDefault();
        addMusicQuery.refetch();
    }

    return (
        <div class="p-6 bg-white" style="width: 40rem; height: 24rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback}>close</button>
            </div>
            <form onSubmit={addMusic} class="flex flex-col items-center">
                <div class="flex items-center m-4">
                    <label for="title" class="text-lg m-2">Title</label>
                    <input id="title" class="border-2 m-2 w-60 h-8" onChange={(event) => setTitle(event.target.value)} required/>
                </div>
                <div class="flex items-center m-4">
                    <label for="artist" class="text-lg m-2">Artist</label>
                    <input id="artist" class="border-2 m-2 w-60 h-8" onChange={(event) => setArtist(event.target.value)} required/>
                </div>
                <input ref={musicInput} type="file" id="addFile" class="w-80 m-6 mb-8" required/>
                <button class="inline-flex items-center border-2 rounded p-3 bg-neutral-400" disabled={addMusicQuery.isFetching}>
                    <span class="mr-2">Add music</span>
                    <Show when={addMusicQuery.isFetching}>
                        <LoadingSpinner/>
                    </Show>
                </button>
            </form>
        </div>
    )
}

export default MusicModal;
