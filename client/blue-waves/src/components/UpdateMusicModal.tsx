import { createSignal, createResource, onMount, Switch, Match, Accessor, Resource, Setter, Show } from "solid-js";
import { until } from "@solid-primitives/promise"; 
import { openDB } from "idb";
import { api } from "../index.tsx";
import LoadingSpinner from "../components/LoadingSpinner";

// Expected fields for each music entry
interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const UpdateMusicModal = (props: { token: string, musicId: Accessor<string>, setMusicId: Setter<string>, closeCallback: () => void, musicEntries: Resource<MusicEntry[]>, setMusicEntries: Setter<MusicEntry[] | undefined>, coverArtUrl: Accessor<string>, fetchCoverArtLoading: Accessor<boolean>}) => {
    const [title, setTitle] = createSignal("");
    const [artist, setArtist] = createSignal("");
    let artInput!: HTMLInputElement;

    const [setCoverArtLoading, setSetCoverArtLoading] = createSignal(false);
    const [deleteMusicLoading, setDeleteMusicLoading] = createSignal(false);

    onMount(() => {
        const musicEntry = props.musicEntries()!.find((musicEntry) => musicEntry["music_id"] === props.musicId());
        setTitle(musicEntry!["title"]);
        setArtist(musicEntry!["artist"]);
    })

    const [coverArtFile] = createResource(async () => {
        await until(() => !props.fetchCoverArtLoading());
        return props.coverArtUrl();
    });

    const updateMusic = async() => {
        // Update music metadata
        await api.patch(`users/music/${props.musicId()}`, {
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
        const updateIndex = newMusicEntries.findIndex((entry) => entry["music_id"] === props.musicId());
        newMusicEntries[updateIndex] = {"music_id": props.musicId(), "title": title(), "artist": artist()};
        props.setMusicEntries(newMusicEntries);
    }

    const deleteMusic = async(event: Event) => {
        event.preventDefault();
        setDeleteMusicLoading(true);
        try {
            // Delete music
            await api.delete(`users/music/${props.musicId()}`, {
                headers: {
                    "Authorization": `Bearer ${props.token}`
                }
            });

            // Delete music entry
            const newMusicEntries = [...props.musicEntries()!];
            const deleteIndex = newMusicEntries.findIndex((entry) => entry["music_id"] === props.musicId());
            newMusicEntries.splice(deleteIndex, 1);
            props.setMusicEntries(newMusicEntries);

            // Delete cache entry
            const db = await openDB("musicFileDB", 1, {
                upgrade(database) {
                    database.createObjectStore("musicFiles", { keyPath: "music_id" });
                    database.createObjectStore("coverArtFiles", { keyPath: "music_id" });
                },
            })
            await db.delete("musicFiles", props.musicId());
            await db.delete("coverArtFiles", props.musicId());

            // Close modal
            props.closeCallback();
        } catch {
            setDeleteMusicLoading(false);
        }
    }

    const setCoverArt = async () => {
        // Create form data
        const data = new FormData();
        data.append("artFile", artInput.files![0]);

        // Set cover art
        setSetCoverArtLoading(true);
        try {
            await api.put(`users/music/${props.musicId()}/cover-art`, {
                headers: {
                    "Authorization": `Bearer ${props.token}`
                },
                body: data
            });

            // Invalidate cover art cache
            props.setMusicId("");
        } catch {
            setSetCoverArtLoading(false);
        }
    }

    const handleUpdate = async (event: Event) => {
        event.preventDefault();
        // Change title and artist
        const updatePromises = [updateMusic()];

        // Change cover art if new one was provided
        if (artInput.files!.length === 1) {
            updatePromises.push(setCoverArt());
        }

        // Close modal
        await Promise.all(updatePromises)
        props.closeCallback();
    }

    return (
        <div class="p-6 bg-white" style="width: 60rem; height: 24rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback} class="mx-5">close</button>
                <button onClick={deleteMusic}>delete</button>
            </div>
            <div class="flex justify-around">
                <form onSubmit={handleUpdate} class="flex flex-col justify-center items-center">
                    <div class="flex items-center m-4">
                        <label for="title" class="text-lg m-2">Title</label>
                        <input id="title" class="border-2 m-2 w-60 h-8" value={title()} onChange={(event) => setTitle(event.target.value)}/>
                    </div>
                    <div class="flex items-center m-4">
                        <label for="artist" class="text-lg m-2">Artist</label>
                        <input id="artist" class="border-2 m-2 w-60 h-8" value={artist()} onChange={(event) => setArtist(event.target.value)}/>
                    </div>
                    <input ref={artInput} type="file" id="artFile" class="w-80 m-6 mb-8"/>
                    <button class="inline-flex items-center border-2 rounded p-3 bg-neutral-400" disabled={setCoverArtLoading()}>
                        <Switch fallback={<span class="mr-2">Update music</span>}>
                            <Match when={setCoverArtLoading()}>
                                <span class="mr-2">Updating</span>
                            </Match>
                            <Match when={deleteMusicLoading()}>
                                <span class="mr-2">Deleting</span>
                            </Match>
                        </Switch>
                        <Show when={setCoverArtLoading() || deleteMusicLoading()}>
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
