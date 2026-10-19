import math
import numpy as np

def compute_cosine_similarity(embedding1: np.ndarray, embedding2: np.ndarray) -> float:
    """
    Computes cosine similarity between two 512-D embedding vectors:
    cos_sim = (u . v) / (||u||_2 * ||v||_2)
    
    Mathematical Properties:
    - Range: [-1.0, 1.0]
    - +1.0 represents identical feature orientation (perfect biometric match)
    -  0.0 represents orthogonal vectors (unrelated / random feature vectors)
    - -1.0 represents diametrically inverted vectors
    - Higher value indicates GREATER biometric similarity.
    - Decision rule: match if similarity >= SIMILARITY_THRESHOLD.
    """
    vec1 = embedding1.flatten().astype(np.float32)
    vec2 = embedding2.flatten().astype(np.float32)
    
    norm1 = np.linalg.norm(vec1)
    norm2 = np.linalg.norm(vec2)
    
    if norm1 == 0.0 or norm2 == 0.0:
        return 0.0
    
    sim = np.dot(vec1, vec2) / (norm1 * norm2)
    # Clip between -1.0 and 1.0 to guard against floating point inaccuracies
    return float(np.clip(sim, -1.0, 1.0))

def cosine_similarity_to_cosine_distance(similarity: float) -> float:
    """
    Converts cosine similarity into cosine distance:
    d_cos = 1.0 - cos_sim
    Range: [0.0, 2.0]. Lower values indicate GREATER similarity.
    """
    return float(np.clip(1.0 - similarity, 0.0, 2.0))

def cosine_similarity_to_l2_distance(similarity: float) -> float:
    """
    Converts cosine similarity of two L2-normalized unit vectors into Euclidean (L2) distance:
    ||u - v||_2 = sqrt(2 * (1.0 - cos_sim))
    Range: [0.0, 2.0]. Lower values indicate GREATER similarity.
    """
    cos_clamped = max(-1.0, min(1.0, similarity))
    return float(math.sqrt(max(0.0, 2.0 * (1.0 - cos_clamped))))

def aggregate_embeddings(embeddings_list: list[np.ndarray]) -> np.ndarray:
    """
    Computes mean embedding from multiple valid enrollment samples and applies L2 normalization.
    """
    if not embeddings_list:
        raise ValueError("Cannot aggregate empty embeddings list")
    
    stacked = np.stack(embeddings_list, axis=0) # [N, 512]
    mean_vec = np.mean(stacked, axis=0)
    norm = np.linalg.norm(mean_vec)
    if norm > 0:
        mean_vec = mean_vec / norm
    return mean_vec.astype(np.float32)

