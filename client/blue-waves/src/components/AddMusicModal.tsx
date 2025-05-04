import { createSignal, useContext, Resource, Signal, Setter, Show } from "solid-js";
import { AuthContext } from "../index.tsx"; 
import { getToken } from "../utils/token";
import LoadingSpinner from "../components/LoadingSpinner";

// Expected fields for each music entry
interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const AddMusicModal = (props: { closeCallback: () => void, musicEntries: Resource<MusicEntry[]>, setMusicEntries: Setter<MusicEntry[] | undefined>}) => {
    let title = "";
    let artist = "";

    const [addMusicLoading, setAddMusicLoading] = createSignal(false);

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    let musicInput!: HTMLInputElement;
    let artInput!: HTMLInputElement;

    const addMusic = async (event: Event) => {
        // Prevent refresh
        event.preventDefault();

        // Create form data
        const formData = new FormData();
        formData.append("title", title);
        formData.append("artist", artist);
        formData.append("musicFile", musicInput.files![0]);
        if (artInput.files!.length !== 0) {
            formData.append("artFile", artInput.files![0]);
        }

        setAddMusicLoading(true);
        const response = await fetch("http://localhost:8080/api/v1/users/music", {
            method: "POST",
            headers: { "Authorization": `Bearer ${token()}` },
            body: formData
        });

        if (response.ok) {
            // Add music entry to list
            const newMusicEntries = [...props.musicEntries()!];
            newMusicEntries!.unshift(await response!.json());
            props.setMusicEntries(newMusicEntries);

            // Close modal
            props.closeCallback();
        } else if (response.status === 401) {
            setToken(await getToken());
            await addMusic(event);
        }
        setAddMusicLoading(false);
    }

    return (
        <div class="p-6 bg-white" style="width: 40rem; height: 28rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback}>close</button>
            </div>
            <form onSubmit={addMusic} class="flex flex-col items-center">
                <div class="flex items-center m-4">
                    <label for="title" class="text-lg m-2">Title</label>
                    <input id="title" class="border-2 m-2 w-60 h-8" onChange={(event) => {title = event.target.value}} maxlength={150} required/>
                </div>
                <div class="flex items-center m-4">
                    <label for="artist" class="text-lg m-2">Artist</label>
                    <input id="artist" class="border-2 m-2 w-60 h-8" onChange={(event) => {artist = event.target.value}} maxlength={100} required/>
                </div>
                <input ref={musicInput} type="file" id="musicFile" class="w-80 m-6 mb-4" required/>
                <input ref={artInput} type="file" id="artFile" class="w-80 m-6 mb-8"/>
                <button class="inline-flex items-center border-2 rounded p-3 bg-neutral-400" disabled={addMusicLoading()}>
                    <span class="mr-2">Add music</span>
                    <Show when={addMusicLoading()}>
                        <LoadingSpinner/>
                    </Show>
                </button>
            </form>
        </div>
    )
}

export default AddMusicModal;
