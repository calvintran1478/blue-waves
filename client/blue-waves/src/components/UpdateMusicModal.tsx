import { createSignal, createResource, onMount, Accessor, Resource, Setter, Show } from "solid-js";
import { createQuery } from "@tanstack/solid-query";
import { api } from "../index.tsx";
import LoadingSpinner from "../components/LoadingSpinner";

// Expected fields for each music entry
interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const UpdateMusicModal = (props: { token: string, music_id: Accessor<string>, closeCallback: () => void, musicEntries: Resource<MusicEntry[]>, setMusicEntries: Setter<MusicEntry[] | undefined>}) => {
    const [title, setTitle] = createSignal("");
    const [artist, setArtist] = createSignal("");
    let artInput!: HTMLInputElement;

    onMount(() => {
        const musicEntry = props.musicEntries()!.find((musicEntry) => musicEntry["music_id"] === props.music_id());
        setTitle(musicEntry!["title"]);
        setArtist(musicEntry!["artist"]);
    })

    const [coverArtFile] = createResource(props.token, async () => {
        // Get cover art
        const musicArtResponse = await api.get(`users/music/${props.music_id()}/cover-art`, {
            headers: {
                "Authorization": `Bearer ${props.token}`
            }
        });

        // Decode data as an image
        const imageBuffer = await musicArtResponse.arrayBuffer();
        const blob = new Blob([imageBuffer])
        const url = window.URL.createObjectURL(blob);
        return url;
    });

    const updateMusicQuery = createQuery(() => ({
        queryKey: ["UpdateMusic"],
        queryFn: async () => {
            // Update music metadata
            await api.patch(`users/music/${props.music_id()}`, {
                headers: {
                    "Authorization": `Bearer ${props.token}`
                },
                json: {
                    title: title(),
                    artist: artist()
                }
            });

            // Update music entry
            const newMusicEntries = [...props.musicEntries()!];
            const updateIndex = newMusicEntries.findIndex((entry) => entry["music_id"] === props.music_id());
            newMusicEntries[updateIndex] = {"music_id": props.music_id(), "title": title(), "artist": artist()};
            props.setMusicEntries(newMusicEntries);

            return null;
        }
    }));

    const setCoverArtQuery = createQuery(() => ({
        queryKey: ["SetCoverArt"],
        queryFn: async () => {
            // Create form data
            const data = new FormData();
            data.append("artFile", artInput.files![0]);

            // Set cover art
            await api.put(`users/music/${props.music_id()}/cover-art`, {
                headers: {
                    "Authorization": `Bearer ${props.token}`
                },
                body: data
            });

            return null;
        }
    }));

    const updateMusic = (event: Event) => {
        event.preventDefault();
        // Change title and artist
        updateMusicQuery.refetch();

        // Change cover art if new one was provided
        if (artInput.files!.length === 1) {
            setCoverArtQuery.refetch();
        }

        // Close modal
        props.closeCallback();
    }

    return (
        <div class="p-6 bg-white" style="width: 60rem; height: 24rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback}>close</button>
            </div>
            <div class="flex justify-around">
                <form onSubmit={updateMusic} class="flex flex-col justify-center items-center">
                    <div class="flex items-center m-4">
                        <label for="title" class="text-lg m-2">Title</label>
                        <input id="title" class="border-2 m-2 w-60 h-8" value={title()} onChange={(event) => setTitle(event.target.value)}/>
                    </div>
                    <div class="flex items-center m-4">
                        <label for="artist" class="text-lg m-2">Artist</label>
                        <input id="artist" class="border-2 m-2 w-60 h-8" value={artist()} onChange={(event) => setArtist(event.target.value)}/>
                    </div>
                    <input ref={artInput} type="file" id="artFile" class="w-80 m-6 mb-8"/>
                    <button class="inline-flex items-center border-2 rounded p-3 bg-neutral-400" disabled={setCoverArtQuery.isFetching}>
                        <span class="mr-2">Update music</span>
                        <Show when={setCoverArtQuery.isFetching}>
                            <LoadingSpinner/>
                        </Show>
                    </button>
                </form>
                <img src={coverArtFile()} class="w-80 h-72"/>
            </div>
        </div>
    )
}

export default UpdateMusicModal;
