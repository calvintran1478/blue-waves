import { createSignal } from "solid-js";
import { createQuery } from "@tanstack/solid-query";
import { api } from "../index.tsx";

const MusicModal = (props: { token: string, closeCallback: () => void }) => {
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
            await api.post("users/music", {
                headers: {
                    "Authorization": `Bearer ${props.token}`
                },
                body: data
            });

            // Close modal
            props.closeCallback();

            return null;
        }
    }));

    const addMusic = (event: Event) => {
        event.preventDefault();
        addMusicQuery.refetch();
    }

    return(
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
                <button class="border-2 rounded p-2">Add music</button>
            </form>
        </div>
    )
}

export default MusicModal;
