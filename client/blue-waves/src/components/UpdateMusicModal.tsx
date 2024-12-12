import { createSignal, createResource, onMount, Switch, Match, Accessor, Resource, Setter, Show } from "solid-js";
import { until } from "@solid-primitives/promise"; 
import { createQuery, CreateQueryResult } from "@tanstack/solid-query";
import { api } from "../index.tsx";
import LoadingSpinner from "../components/LoadingSpinner";

// Expected fields for each music entry
interface MusicEntry {
    music_id: string,
    title: string,
    artist: string
}

const UpdateMusicModal = (props: { token: string, musicId: Accessor<string>, setMusicId: Setter<string>, closeCallback: () => void, musicEntries: Resource<MusicEntry[]>, setMusicEntries: Setter<MusicEntry[] | undefined>, coverArtUrl: Accessor<string>, fetchCoverArtQuery: CreateQueryResult}) => {
    const [title, setTitle] = createSignal("");
    const [artist, setArtist] = createSignal("");
    let artInput!: HTMLInputElement;

    onMount(() => {
        const musicEntry = props.musicEntries()!.find((musicEntry) => musicEntry["music_id"] === props.musicId());
        setTitle(musicEntry!["title"]);
        setArtist(musicEntry!["artist"]);
    })

    const [coverArtFile] = createResource(async () => {
        await until(() => !props.fetchCoverArtQuery.isFetching)
        return props.coverArtUrl();
    });

    const updateMusicQuery = createQuery(() => ({
        queryKey: ["UpdateMusic"],
        queryFn: async () => {
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

            return null;
        }
    }));

    const deleteMusicQuery = createQuery(() => ({
        queryKey: ["DeleteMusic"],
        queryFn: async () => {
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

            // Close modal
            props.closeCallback();

            return null;
        }
    }))

    const setCoverArtQuery = createQuery(() => ({
        queryKey: ["SetCoverArt"],
        queryFn: async () => {
            // Create form data
            const data = new FormData();
            data.append("artFile", artInput.files![0]);

            // Set cover art
            await api.put(`users/music/${props.musicId()}/cover-art`, {
                headers: {
                    "Authorization": `Bearer ${props.token}`
                },
                body: data
            });

            // Invalidate cover art cache
            props.setMusicId("");

            return null;
        }
    }));

    const updateMusic = async (event: Event) => {
        event.preventDefault();
        // Change title and artist
        const updatePromises = [updateMusicQuery.refetch()];

        // Change cover art if new one was provided
        if (artInput.files!.length === 1) {
            updatePromises.push(setCoverArtQuery.refetch());
        }

        // Close modal
        await Promise.all(updatePromises)
        props.closeCallback();
    }

    const deleteMusic = async (event: Event) => {
        event.preventDefault();
        deleteMusicQuery.refetch();
    }

    return (
        <div class="p-6 bg-white" style="width: 60rem; height: 24rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback} class="mx-5">close</button>
                <button onClick={deleteMusic}>delete</button>
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
                        <Switch fallback={<span class="mr-2">Update music</span>}>
                            <Match when={setCoverArtQuery.isFetching}>
                                <span class="mr-2">Updating</span>
                            </Match>
                            <Match when={deleteMusicQuery.isFetching}>
                                <span class="mr-2">Deleting</span>
                            </Match>
                        </Switch>
                        <Show when={setCoverArtQuery.isFetching || deleteMusicQuery.isFetching}>
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
